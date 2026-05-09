;;; tmux-peek-parser-test.el --- parser tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'tmux-peek-parse)

(ert-deftest tmux-peek-parse-list-sessions-converts-types ()
  (let* ((sep tmux-peek--field-separator)
         (stdout (concat "main" sep "$0" sep "3" sep "1" sep "1715240000\n"))
         (sessions (tmux-peek--parse-list-sessions stdout)))
    (should (equal sessions
                   '((:name "main"
                      :id "$0"
                      :windows 3
                      :attached t
                      :created 1715240000))))))

(ert-deftest tmux-peek-parse-list-panes-converts-types ()
  (let* ((sep tmux-peek--field-separator)
         (stdout (concat "main" sep "1" sep "0" sep "%5" sep "12345" sep
                         "zsh" sep "/tmp" sep "0" sep "120" sep "40\n"))
         (panes (tmux-peek--parse-list-panes stdout)))
    (should (equal panes
                   '((:session "main"
                      :window-index 1
                      :pane-index 0
                      :pane-id "%5"
                      :pane-pid 12345
                      :current-command "zsh"
                      :current-path "/tmp"
                      :active nil
                      :width 120
                      :height 40))))))

(ert-deftest tmux-peek-parse-list-signals-on-wrong-field-count ()
  (should-error
   (tmux-peek--parse-list-sessions "main\x1f$0\n")
   :type 'tmux-peek-error-parse))

(ert-deftest tmux-peek-parse-show-options ()
  (should (equal (tmux-peek--parse-show-options
                  "status on\nbase-index 1\n")
                 '(("status" . "on")
                   ("base-index" . "1")))))

(ert-deftest tmux-peek-parse-show-environment ()
  (should (equal (tmux-peek--parse-show-environment
                  "PATH=/bin\n-OLD\n")
                 '(("PATH" . "/bin")
                   ("OLD")))))

(provide 'tmux-peek-parser-test)
;;; tmux-peek-parser-test.el ends here
