deps:
	tt rocks install luatest
	tt rocks install luacov 0.13.0
	tt rocks install luacov-reporters 0.1.0
	tt rocks install luacheck 0.26.0

build:
	tt rocks make

.PHONY: test
test:
	.rocks/bin/luatest -v --coverage --shuffle all

coverage:
	.rocks/bin/luacov -r summary && cat luacov.report.out

lint:
	.rocks/bin/luacheck --config=.luacheckrc .
