;;; tmux-peek-api-test.el --- public API tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'tmux-peek-api)

(ert-deftest tmux-peek-api-list-panes-maps-value ()
  (let* ((sep tmux-peek--field-separator)
         (stdout (concat "main" sep "1" sep "0" sep "%5" sep "12345" sep
                         "zsh" sep "/tmp" sep "1" sep "120" sep "40\n"))
         captured-args
         captured-result)
    (cl-letf (((symbol-function 'tmux-peek--exec-async)
               (lambda (_executable args callback &optional _opts)
                 (setq captured-args args)
                 (funcall callback
                          (list :ok t :stdout stdout :stderr "" :exit-code 0))
                 :handle)))
      (should (eq (tmux-peek-list-panes-async
                   (lambda (result) (setq captured-result result)))
                  :handle))
      (should (member "list-panes" captured-args))
      (should (plist-get captured-result :ok))
      (should (equal (plist-get captured-result :value)
                     '((:session "main"
                        :window-index 1
                        :pane-index 0
                        :pane-id "%5"
                        :pane-pid 12345
                        :current-command "zsh"
                        :current-path "/tmp"
                        :active t
                        :width 120
                        :height 40)))))))

(ert-deftest tmux-peek-api-kill-pane-builds-only-kill-pane ()
  (let (captured-args captured-result)
    (cl-letf (((symbol-function 'tmux-peek--exec-async)
               (lambda (_executable args callback &optional _opts)
                 (setq captured-args args)
                 (funcall callback
                          (list :ok t :stdout "" :stderr "" :exit-code 0))
                 :handle)))
      (should (eq (tmux-peek-kill-pane-async
                   "%1"
                   (lambda (result) (setq captured-result result)))
                  :handle))
      (should (equal captured-args '("kill-pane" "-t" "%1")))
      (should (equal (plist-get captured-result :value) t)))))

(ert-deftest tmux-peek-api-target-exists-turns-errors-into-nil ()
  (let (captured-result)
    (cl-letf (((symbol-function 'tmux-peek--exec-async)
               (lambda (_executable _args callback &optional _opts)
                 (funcall callback
                          (list :ok nil
                                :error 'tmux-peek-error-no-target
                                :stdout ""
                                :stderr "can't find pane"
                                :exit-code 1))
                 :handle)))
      (tmux-peek-target-exists-p-async
       "%missing" (lambda (result) (setq captured-result result)))
      (should (plist-get captured-result :ok))
      (should-not (plist-get captured-result :value)))))

(provide 'tmux-peek-api-test)
;;; tmux-peek-api-test.el ends here
