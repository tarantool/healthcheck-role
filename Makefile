deps:
	tt rocks install luatest
	tt rocks install luacov 0.13.0
	tt rocks install luacov-reporters 0.1.0
	tt rocks install luacheck 0.26.0
	tt rocks install luacov-coveralls 0.2.3-1 --server=http://luarocks.org

build:
	tt rocks make

.PHONY: test
test:
	.rocks/bin/luatest -v --coverage --shuffle all

coverage:
	.rocks/bin/luacov -r summary && cat luacov.report.out

lint:
	.rocks/bin/luacheck --config=.luacheckrc .


coveralls: coverage
	echo "Send code coverage data to the coveralls.io service"
	.rocks/bin/luacov-coveralls --verbose --repo-token ${REPO_TOKEN}
