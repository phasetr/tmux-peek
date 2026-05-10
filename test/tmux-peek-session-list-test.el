;;; tmux-peek-session-list-test.el --- session list UI tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'tmux-peek-session-list)

(ert-deftest tmux-peek-session-list-entry-formats-session ()
  (should
   (equal
    (tmux-peek-session-list--entry
     '(:name "main" :id "$0" :windows 2 :attached t :created 1715240000))
    '("main" ["main" "$0" "2" "yes" "1715240000"]))))

(ert-deftest tmux-peek-session-list-refresh-renders-sessions ()
  (with-temp-buffer
    (tmux-peek-session-list-mode)
    (let ((tmux-peek-session-list--opts '(:socket-name "peek")))
      (cl-letf (((symbol-function 'tmux-peek-list-sessions-async)
                 (lambda (callback opts)
                   (should (equal opts '(:socket-name "peek")))
                   (funcall callback
                            (list :ok t
                                  :value
                                  '((:name "main"
                                     :id "$0"
                                     :windows 2
                                     :attached nil
                                     :created 1715240000))))
                   :handle)))
        (should (eq (tmux-peek-session-list-refresh) :handle))
        (should (equal tabulated-list-entries
                       '(("main" ["main" "$0" "2" "no" "1715240000"]))))))))

(ert-deftest tmux-peek-session-list-kill-kills-session-and-refreshes ()
  (with-temp-buffer
    (tmux-peek-session-list-mode)
    (let ((tmux-peek-session-list--opts '(:socket-name "peek"))
          killed
          refreshed)
      (cl-letf (((symbol-function 'y-or-n-p)
                 (lambda (_prompt) t))
                ((symbol-function 'tmux-peek-kill-session-async)
                 (lambda (target callback opts)
                   (setq killed (list target opts))
                   (funcall callback
                            (list :ok t :value t :stdout "" :stderr ""))
                   :handle))
                ((symbol-function 'tmux-peek-session-list-refresh)
                (lambda ()
                  (setq refreshed t)
                  :refreshed))
                ((symbol-function 'message)
                 (lambda (&rest _args) nil)))
        (should (eq (tmux-peek-session-list-kill "main") :handle))
        (should (equal killed '("main" (:socket-name "peek"))))
        (should refreshed)))))

(provide 'tmux-peek-session-list-test)
;;; tmux-peek-session-list-test.el ends here
