deps:
	tt rocks install luatest
	tt rocks install luacov 0.13.0
	tt rocks install luacov-reporters 0.1.0


build:
	tt rocks make

test:
	.rocks/bin/luatest -v --coverage --shuffle all

coverage:
	.rocks/bin/luacov -r summary && cat tmp/luacov.report.out
