;;; tmux-peek-error-test.el --- error classifier tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'tmux-peek-error)

(ert-deftest tmux-peek-classify-no-server ()
  (should (eq (tmux-peek--classify-stderr "no server running on /tmp/tmux")
              'tmux-peek-error-no-server)))

(ert-deftest tmux-peek-classify-no-target ()
  (should (eq (tmux-peek--classify-stderr "can't find pane: %999")
              'tmux-peek-error-no-target)))

(ert-deftest tmux-peek-classify-generic ()
  (should (eq (tmux-peek--classify-stderr "bad value")
              'tmux-peek-error-exec)))

(provide 'tmux-peek-error-test)
;;; tmux-peek-error-test.el ends here
