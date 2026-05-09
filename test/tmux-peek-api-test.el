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

(ert-deftest tmux-peek-api-target-exists-preserves-non-target-errors ()
  (let (captured-result)
    (cl-letf (((symbol-function 'tmux-peek--exec-async)
               (lambda (_executable _args callback &optional _opts)
                 (funcall callback
                          (list :ok nil
                                :error 'tmux-peek-error-not-found
                                :stdout ""
                                :stderr "missing"
                                :exit-code nil))
                 :handle)))
      (tmux-peek-target-exists-p-async
       "%missing" (lambda (result) (setq captured-result result)))
      (should-not (plist-get captured-result :ok))
      (should (eq (plist-get captured-result :error)
                  'tmux-peek-error-not-found)))))

(ert-deftest tmux-peek-api-server-running-no-server-is-false ()
  (let (captured-result)
    (cl-letf (((symbol-function 'tmux-peek--exec-async)
               (lambda (_executable _args callback &optional _opts)
                 (funcall callback
                          (list :ok nil
                                :error 'tmux-peek-error-no-server
                                :stdout ""
                                :stderr "no server running"
                                :exit-code 1))
                 :handle)))
      (tmux-peek-server-running-p-async
       (lambda (result) (setq captured-result result)))
      (should (plist-get captured-result :ok))
      (should-not (plist-get captured-result :value)))))

(ert-deftest tmux-peek-api-server-running-preserves-not-found ()
  (let (captured-result)
    (cl-letf (((symbol-function 'tmux-peek--exec-async)
               (lambda (_executable _args callback &optional _opts)
                 (funcall callback
                          (list :ok nil
                                :error 'tmux-peek-error-not-found
                                :stdout ""
                                :stderr "missing"
                                :exit-code nil))
                 :handle)))
      (tmux-peek-server-running-p-async
       (lambda (result) (setq captured-result result)))
      (should-not (plist-get captured-result :ok))
      (should (eq (plist-get captured-result :error)
                  'tmux-peek-error-not-found)))))

(ert-deftest tmux-peek-api-parse-error-returns-clean-failure ()
  (let (captured-result)
    (cl-letf (((symbol-function 'tmux-peek--exec-async)
               (lambda (_executable _args callback &optional _opts)
                 (funcall callback
                          (list :ok t
                                :stdout "too-few-fields"
                                :stderr ""
                                :exit-code 0
                                :command '("tmux" "list-sessions")))
                 :handle)))
      (tmux-peek-list-sessions-async
       (lambda (result) (setq captured-result result)))
      (should-not (plist-get captured-result :ok))
      (should (eq (plist-get captured-result :error)
                  'tmux-peek-error-parse))
      (should (equal (plist-get captured-result :command)
                     '("tmux" "list-sessions"))))))

(provide 'tmux-peek-api-test)
;;; tmux-peek-api-test.el ends here
