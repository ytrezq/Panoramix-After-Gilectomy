// A vector with room for N elements in itself: the elements of a tuple
// being made (most have a handful) without a malloc.
#pragma once

#include <cstdlib>
#include <cstring>
#include <initializer_list>
#include <new>
#include <span>
#include <type_traits>

#include "core/base.hpp"

namespace pan {

template <class T, usize N = 8>
class SmallVec {
    static_assert(std::is_trivially_copyable_v<T>, "SmallVec holds plain values");

public:
    SmallVec() = default;
    SmallVec(std::initializer_list<T> l) {
        for (const T& x : l) push_back(x);
    }
    explicit SmallVec(std::span<const T> s) { append(s); }
    SmallVec(const SmallVec& o) { append(std::span<const T>(o.data(), o.size())); }
    SmallVec& operator=(const SmallVec& o) {
        if (this != &o) {
            n_ = 0;
            append(std::span<const T>(o.data(), o.size()));
        }
        return *this;
    }
    ~SmallVec() {
        if (heap_) std::free(heap_);
    }

    T* data() { return heap_ ? heap_ : inline_; }
    const T* data() const { return heap_ ? heap_ : inline_; }
    usize size() const { return n_; }
    bool empty() const { return n_ == 0; }
    T& operator[](usize i) { return data()[i]; }
    const T& operator[](usize i) const { return data()[i]; }
    T* begin() { return data(); }
    T* end() { return data() + n_; }
    const T* begin() const { return data(); }
    const T* end() const { return data() + n_; }
    T& back() { return data()[n_ - 1]; }
    const T& back() const { return data()[n_ - 1]; }
    operator std::span<const T>() const { return {data(), n_}; }
    std::span<const T> span() const { return {data(), n_}; }

    void push_back(const T& x) {
        if (PAN_UNLIKELY(n_ == cap_)) {
            T copy = x;  // x may be in the buffer grow frees
            std::free(grow(n_ + 1));
            data()[n_++] = copy;
            return;
        }
        data()[n_++] = x;
    }
    void pop_back() { n_--; }
    void append(std::span<const T> s) {
        void* old = n_ + s.size() > cap_ ? grow(n_ + s.size()) : nullptr;
        if (!s.empty()) std::memcpy(data() + n_, s.data(), s.size() * sizeof(T));
        n_ += s.size();
        std::free(old);  // after the copy: s may point into it
    }
    void insert_front(const T& x) {
        T copy = x;  // x may be in the buffer grow frees
        if (n_ == cap_) std::free(grow(n_ + 1));
        std::memmove(data() + 1, data(), n_ * sizeof(T));
        data()[0] = copy;
        n_++;
    }
    void resize(usize n) {
        if (n > cap_) std::free(grow(n));
        if (n > n_) std::memset(data() + n_, 0, (n - n_) * sizeof(T));
        n_ = n;
    }
    void clear() { n_ = 0; }

private:
    // a bigger buffer holding the elements; returns the old heap buffer
    // (nullptr: none), which the caller frees once it no longer reads it
    [[nodiscard]] void* grow(usize need) {
        usize cap = cap_ * 2;
        if (cap < need) cap = need;
        T* p = static_cast<T*>(std::malloc(cap * sizeof(T)));
        // the system gave no more: the job maps bad_alloc to MemoryLimit
        if (PAN_UNLIKELY(!p)) throw std::bad_alloc();
        std::memcpy(p, data(), n_ * sizeof(T));
        void* old = heap_;
        heap_ = p;
        cap_ = cap;
        return old;
    }

    T* heap_ = nullptr;
    usize n_ = 0;
    usize cap_ = N;
    T inline_[N];
};

// python's three-valued answers (and the comparisons' fourth: the
// algebra's CannotCompare)
enum class Tri : i8 { False = 0, True = 1, None = -1, Cannot = -2 };
inline Tri tri(bool b) { return b ? Tri::True : Tri::False; }

}  // namespace pan
