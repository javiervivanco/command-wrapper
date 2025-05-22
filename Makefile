docs: docs-en docs-es

docs-en:
	@echo "Building English documentation..."
	raco scribble +m --html --dest ./doc scribblings/cmd-wrapper.scrbl
	@echo "English documentation built in ./doc/cmd-wrapper/index.html"

docs-es:
	@echo "Building Spanish documentation..."
	raco scribble +m --html --dest ./doc-es scribblings/cmd-wrapper-es.scrbl
	@echo "Spanish documentation built in ./doc-es/cmd-wrapper-es/index.html"

clean-docs:
	@echo "Cleaning documentation..."
	rm -rf ./doc ./doc-es
make test:
	raco test main.rkt
.PHONY: docs docs-en docs-es clean-docs test
