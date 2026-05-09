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

(ert-deftest tmux-peek-api-list-clients-maps-value ()
  (let* ((sep tmux-peek--field-separator)
         (stdout (concat "/dev/ttys001" sep "/dev/ttys001" sep "main" sep
                         "23456" sep "100" sep "30" sep "1715240010\n"))
         captured-args
         captured-result)
    (cl-letf (((symbol-function 'tmux-peek--exec-async)
               (lambda (_executable args callback &optional _opts)
                 (setq captured-args args)
                 (funcall callback
                          (list :ok t :stdout stdout :stderr "" :exit-code 0))
                 :handle)))
      (tmux-peek-list-clients-async
       (lambda (result) (setq captured-result result)))
      (should (member "list-clients" captured-args))
      (should (equal (plist-get captured-result :value)
                     '((:name "/dev/ttys001"
                        :tty "/dev/ttys001"
                        :session "main"
                        :pid 23456
                        :width 100
                        :height 30
                        :created 1715240010)))))))

(ert-deftest tmux-peek-api-list-buffers-maps-value ()
  (let* ((sep tmux-peek--field-separator)
         (stdout (concat "buffer0" sep "5" sep "1715240020" sep "hello\n"))
         captured-args
         captured-result)
    (cl-letf (((symbol-function 'tmux-peek--exec-async)
               (lambda (_executable args callback &optional _opts)
                 (setq captured-args args)
                 (funcall callback
                          (list :ok t :stdout stdout :stderr "" :exit-code 0))
                 :handle)))
      (tmux-peek-list-buffers-async
       (lambda (result) (setq captured-result result)))
      (should (member "list-buffers" captured-args))
      (should (equal (plist-get captured-result :value)
                     '((:name "buffer0"
                        :size 5
                        :created 1715240020
                        :sample "hello")))))))

(ert-deftest tmux-peek-api-display-message-trims-value ()
  (let (captured-args captured-result)
    (cl-letf (((symbol-function 'tmux-peek--exec-async)
               (lambda (_executable args callback &optional _opts)
                 (setq captured-args args)
                 (funcall callback
                          (list :ok t :stdout "%1\n" :stderr "" :exit-code 0))
                 :handle)))
      (tmux-peek-display-message-async
       "#{pane_id}" (lambda (result) (setq captured-result result)))
      (should (equal captured-args
                     '("display-message" "-p" "#{pane_id}")))
      (should (equal (plist-get captured-result :value) "%1")))))

(ert-deftest tmux-peek-api-show-buffer-keeps-value ()
  (let (captured-args captured-result)
    (cl-letf (((symbol-function 'tmux-peek--exec-async)
               (lambda (_executable args callback &optional _opts)
                 (setq captured-args args)
                 (funcall callback
                          (list :ok t
                                :stdout "buffer text\n"
                                :stderr ""
                                :exit-code 0))
                 :handle)))
      (tmux-peek-show-buffer-async
       (lambda (result) (setq captured-result result))
       '(:buffer-name "buffer0"))
      (should (equal captured-args '("show-buffer" "-b" "buffer0")))
      (should (equal (plist-get captured-result :value) "buffer text\n")))))

(ert-deftest tmux-peek-api-version-trims-value ()
  (let (captured-args captured-result)
    (cl-letf (((symbol-function 'tmux-peek--exec-async)
               (lambda (_executable args callback &optional _opts)
                 (setq captured-args args)
                 (funcall callback
                          (list :ok t
                                :stdout "tmux 3.6a\n"
                                :stderr ""
                                :exit-code 0))
                 :handle)))
      (tmux-peek-version-async
       (lambda (result) (setq captured-result result)))
      (should (equal captured-args '("-V")))
      (should (equal (plist-get captured-result :value) "tmux 3.6a")))))

(ert-deftest tmux-peek-api-kill-session-builds-only-kill-session ()
  (let (captured-args captured-result)
    (cl-letf (((symbol-function 'tmux-peek--exec-async)
               (lambda (_executable args callback &optional _opts)
                 (setq captured-args args)
                 (funcall callback
                          (list :ok t :stdout "" :stderr "" :exit-code 0))
                 :handle)))
      (should (eq (tmux-peek-kill-session-async
                   "main"
                   (lambda (result) (setq captured-result result)))
                  :handle))
      (should (equal captured-args '("kill-session" "-t" "main")))
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

(ert-deftest tmux-peek-api-target-exists-turns-empty-success-into-nil ()
  (let (captured-result)
    (cl-letf (((symbol-function 'tmux-peek--exec-async)
               (lambda (_executable _args callback &optional _opts)
                 (funcall callback
                          (list :ok t
                                :stdout "\n"
                                :stderr ""
                                :exit-code 0))
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

(ert-deftest tmux-peek-api-show-options-maps-value ()
  (let (captured-result)
    (cl-letf (((symbol-function 'tmux-peek--exec-async)
               (lambda (_executable _args callback &optional _opts)
                 (funcall callback
                          (list :ok t
                                :stdout "status on\n"
                                :stderr ""
                                :exit-code 0))
                 :handle)))
      (tmux-peek-show-options-async
       (lambda (result) (setq captured-result result)))
      (should (equal (plist-get captured-result :value)
                     '(("status" . "on")))))))

(ert-deftest tmux-peek-api-show-environment-maps-value ()
  (let (captured-result)
    (cl-letf (((symbol-function 'tmux-peek--exec-async)
               (lambda (_executable _args callback &optional _opts)
                 (funcall callback
                          (list :ok t
                                :stdout "PATH=/bin\n-OLD\n"
                                :stderr ""
                                :exit-code 0))
                 :handle)))
      (tmux-peek-show-environment-async
       (lambda (result) (setq captured-result result)))
      (should (equal (plist-get captured-result :value)
                     '(("PATH" . "/bin") ("OLD")))))))

(provide 'tmux-peek-api-test)
;;; tmux-peek-api-test.el ends here
