munged-simple: $(wildcard ../contracts/*.sol) patches/applyHarnessRecapitalizationModule.patch
	@rm -rf munged-simple
	@cp -r ../contracts munged-simple
	@patch -p2 -d munged-simple < patches/applyHarnessRecapitalizationModule.patch

clean:
	rm -rf munged-simple
