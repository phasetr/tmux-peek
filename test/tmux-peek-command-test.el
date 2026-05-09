;;; tmux-peek-command-test.el --- command builder tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'tmux-peek-command)
(require 'tmux-peek-api)

(ert-deftest tmux-peek-build-args-adds-socket-name ()
  (should (equal (tmux-peek--build-args
                  "list-sessions" '(:socket-name "peek") '("-F" "x"))
                 '("-L" "peek" "list-sessions" "-F" "x"))))

(ert-deftest tmux-peek-format-spec-uses-fields ()
  (should (equal (tmux-peek--format-spec
                  '((:key :name :format "session_name" :type string)
                    (:key :id :format "session_id" :type string)))
                 (concat "#{session_name}" tmux-peek--field-separator
                         "#{session_id}"))))

(ert-deftest tmux-peek-kill-pane-requires-target ()
  (should-error (tmux-peek--kill-pane-args nil)))

(ert-deftest tmux-peek-show-options-builds-scope-args ()
  (should (equal (tmux-peek--show-options-args
                  '(:socket-name "peek" :global t :option "status"))
                 '("-L" "peek" "show-options" "-g" "status"))))

(ert-deftest tmux-peek-show-environment-builds-variable-args ()
  (should (equal (tmux-peek--show-environment-args
                  '(:socket-name "peek" :target "s" :variable "PATH"))
                 '("-L" "peek" "show-environment" "-t" "s" "PATH"))))

(ert-deftest tmux-peek-dangerous-kill-apis-are-not-defined ()
  (should-not (fboundp 'tmux-peek-kill-session-async))
  (should-not (fboundp 'tmux-peek-kill-window-async))
  (should-not (fboundp 'tmux-peek-kill-server-async)))

(provide 'tmux-peek-command-test)
;;; tmux-peek-command-test.el ends here
