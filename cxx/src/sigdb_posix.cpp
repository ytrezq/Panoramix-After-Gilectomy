// The signature database's platform layer, POSIX: the mapping of a file, its
// stamp, the cache directory, a file written then renamed. (The MinGW port
// adds sigdb_win32.cpp: CreateFileMapping, %LOCALAPPDATA%, MoveFileEx.)
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <climits>
#include <cstdlib>
#include <cstring>
#include <system_error>

#include "sigdb_impl.hpp"

namespace pan::sigdb {

namespace {

constexpr std::size_t max_read = std::size_t{1} << 30;  // what isn't mapped: read, 1 GiB at most

std::string os_error(int err) { return std::generic_category().message(err); }

struct Fd {
    int fd;
    ~Fd()
    {
        if (fd >= 0)
            ::close(fd);
    }
};

}  // namespace

std::unique_ptr<Mapping> Mapping::open(const std::filesystem::path& path)
{
    Fd f{::open(path.c_str(), O_RDONLY | O_CLOEXEC)};
    if (f.fd < 0)
        throw Error(Error::Code::failed, "can't read " + path.string() + ": " + os_error(errno));
    struct stat st;
    if (::fstat(f.fd, &st) != 0)
        throw Error(Error::Code::failed, "can't read " + path.string() + ": " + os_error(errno));
    if (S_ISREG(st.st_mode)) {
        auto size = static_cast<std::size_t>(st.st_size);
        if (size == 0)
            return std::unique_ptr<Mapping>(new Mapping(nullptr, 0));
        void* a = ::mmap(nullptr, size, PROT_READ, MAP_PRIVATE, f.fd, 0);
        if (a == MAP_FAILED)
            throw Error(Error::Code::failed, "can't map " + path.string() + ": " + os_error(errno));
        return std::unique_ptr<Mapping>(new Mapping(static_cast<const std::uint8_t*>(a), size));
    }
    // a pipe, a device: read whole
    std::unique_ptr<Mapping> m(new Mapping(nullptr, 0));
    std::vector<std::uint8_t>& buf = m->read_;
    for (;;) {
        if (buf.size() == buf.capacity())
            buf.reserve(std::max<std::size_t>(buf.capacity() * 2, 1 << 20));
        std::size_t at = buf.size();
        buf.resize(buf.capacity());
        ssize_t n = ::read(f.fd, buf.data() + at, buf.size() - at);
        if (n < 0 && errno == EINTR) {
            buf.resize(at);
            continue;
        }
        if (n < 0)
            throw Error(Error::Code::failed, "can't read " + path.string() + ": " + os_error(errno));
        buf.resize(at + static_cast<std::size_t>(n));
        if (n == 0)
            break;
        if (buf.size() > max_read)
            throw Error(Error::Code::failed, path.string() + ": more than 1 GiB");
    }
    m->data_ = buf.data();
    m->size_ = buf.size();
    return m;
}

Mapping::~Mapping()
{
    if (read_.empty() && size_)
        ::munmap(const_cast<std::uint8_t*>(data_), size_);
}

namespace platform {

std::optional<Stamp> stamp(const std::filesystem::path& path) noexcept
{
    struct stat st;
    if (::stat(path.c_str(), &st) != 0 || !S_ISREG(st.st_mode))
        return std::nullopt;
    return Stamp{static_cast<std::uint64_t>(st.st_size),
                 static_cast<std::int64_t>(st.st_mtim.tv_sec) * 1000000000 + st.st_mtim.tv_nsec};
}

std::optional<std::filesystem::path> real_path(const std::filesystem::path& path) noexcept
{
    char* r = ::realpath(path.c_str(), nullptr);
    if (!r)
        return std::nullopt;
    std::optional<std::filesystem::path> res;
    try {
        res = std::filesystem::path(r);
    } catch (...) {
    }
    std::free(r);
    return res;
}

std::filesystem::path cache_dir()
{
    if (const char* x = std::getenv("XDG_CACHE_HOME"); x && *x)
        return std::filesystem::path(x) / "panoramix";
    if (const char* h = std::getenv("HOME"); h && *h)
        return std::filesystem::path(h) / ".cache" / "panoramix";
    return {};
}

namespace {
std::atomic<unsigned> tmp_counter{0};  // (two builds of one process at once)
}

AtomicFile::AtomicFile(const std::filesystem::path& path) : path_(path)
{
    std::error_code ec;
    if (path.has_parent_path())
        std::filesystem::create_directories(path.parent_path(), ec);  // (else: open says)
    tmp_ = path;
    tmp_ += "." + std::to_string(::getpid()) + "." + std::to_string(tmp_counter++) + ".tmp";
    // a file of that name left there (or a link planted) goes; made anew
    ::unlink(tmp_.c_str());
    fd_ = ::open(tmp_.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0644);
    if (fd_ < 0)
        throw Error(Error::Code::failed, "can't write " + tmp_.string() + ": " + os_error(errno));
    buffer_.reserve(1 << 20);
}

AtomicFile::~AtomicFile()
{
    if (fd_ >= 0)
        ::close(fd_);
    if (!committed_)
        ::unlink(tmp_.c_str());
}

void AtomicFile::write(std::span<const std::uint8_t> data)
{
    if (buffer_.size() + data.size() > buffer_.capacity())
        flush();
    if (data.size() >= buffer_.capacity()) {
        buffer_.assign(data.begin(), data.end());
        flush();
        return;
    }
    buffer_.insert(buffer_.end(), data.begin(), data.end());
}

void AtomicFile::flush()
{
    const std::uint8_t* p = buffer_.data();
    std::size_t left = buffer_.size();
    while (left) {
        ssize_t n = ::write(fd_, p, left);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            throw Error(Error::Code::failed, "can't write " + tmp_.string() + ": " +
                                                 os_error(n < 0 ? errno : ENOSPC));
        p += n;
        left -= static_cast<std::size_t>(n);
    }
    buffer_.clear();
}

void AtomicFile::commit()
{
    flush();
    if (::fsync(fd_) != 0 && errno != EINVAL)
        throw Error(Error::Code::failed, "can't write " + tmp_.string() + ": " + os_error(errno));
    int fd = fd_;
    fd_ = -1;
    if (::close(fd) != 0)
        throw Error(Error::Code::failed, "can't write " + tmp_.string() + ": " + os_error(errno));
    if (::rename(tmp_.c_str(), path_.c_str()) != 0)
        throw Error(Error::Code::failed, "can't write " + path_.string() + ": " + os_error(errno));
    committed_ = true;
}

}  // namespace platform

}  // namespace pan::sigdb
