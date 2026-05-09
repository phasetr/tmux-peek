EMACS ?= emacs

ELFILES := $(wildcard *.el)
TESTFILES := $(filter-out test/tmux-peek-integration-test.el,$(wildcard test/*.el))
INTEGRATION_TESTFILES := test/tmux-peek-integration-test.el

.PHONY: check compile checkdoc test test-integration clean

check: compile checkdoc test

compile:
	$(EMACS) -Q --batch -L . --eval "(setq load-prefer-newer t)" -f batch-byte-compile $(ELFILES)

checkdoc:
	$(EMACS) -Q --batch -L . --eval "(require 'checkdoc)" --eval "(setq checkdoc-force-docstrings-flag nil)" --eval "(dolist (file command-line-args-left) (checkdoc-file file))" $(ELFILES)

test:
	$(EMACS) -Q --batch -L . --eval "(setq load-prefer-newer t)" $(foreach file,$(TESTFILES),-l $(file)) -f ert-run-tests-batch-and-exit

test-integration:
	$(EMACS) -Q --batch -L . --eval "(setq load-prefer-newer t)" $(foreach file,$(INTEGRATION_TESTFILES),-l $(file)) -f ert-run-tests-batch-and-exit

clean:
	rm -f *.elc test/*.elc
