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
                       '(("main" ["main" "$0" "2" "no" "1715240000"]))))
        (should (string-match-p "d/k delete session" (buffer-string)))
        (should (string-match-p "RET/v/t view tail" (buffer-string)))
        (should (equal (tabulated-list-get-id) "main"))))))

(ert-deftest tmux-peek-session-list-keymap-binds-actions ()
  (with-temp-buffer
    (tmux-peek-session-list-mode)
    (should (eq (key-binding (kbd "RET")) #'tmux-peek-session-list-view))
    (should (eq (key-binding (kbd "v")) #'tmux-peek-session-list-view))
    (should (eq (key-binding (kbd "t")) #'tmux-peek-session-list-view))
    (should (eq (key-binding (kbd "d")) #'tmux-peek-session-list-kill))
    (should (eq (key-binding (kbd "g")) #'tmux-peek-session-list-refresh))
    (should (eq (key-binding (kbd "b")) #'tmux-peek-session-list-back))))

(ert-deftest tmux-peek-session-list-setup-keymap-updates-existing-map ()
  (let ((original-map tmux-peek-session-list-mode-map))
    (unwind-protect
        (let ((stale-map (make-sparse-keymap)))
          (setq tmux-peek-session-list-mode-map stale-map)
          (with-temp-buffer
            (use-local-map stale-map)
            (tmux-peek-session-list--setup-keymap)
            (should (eq (key-binding (kbd "RET"))
                        #'tmux-peek-session-list-view))
            (should (eq (key-binding (kbd "v"))
                        #'tmux-peek-session-list-view))
            (should (eq (key-binding (kbd "t"))
                        #'tmux-peek-session-list-view))
            (should (eq (key-binding (kbd "b"))
                        #'tmux-peek-session-list-back))))
      (setq tmux-peek-session-list-mode-map original-map)
      (tmux-peek-session-list--setup-keymap))))

(ert-deftest tmux-peek-session-list-view-captures-first-pane ()
  (with-temp-buffer
    (tmux-peek-session-list-mode)
    (let ((tmux-peek-session-list--opts '(:socket-name "peek"))
          (tmux-peek-session-list-tail-lines 20)
          pane-call
          capture-call)
      (cl-letf (((symbol-function 'tmux-peek-list-panes-async)
                 (lambda (callback opts)
                   (setq pane-call opts)
                   (funcall callback
                            (list :ok t
                                  :value '((:pane-id "%1")
                                           (:pane-id "%2"))))
                   :pane-handle))
                ((symbol-function 'tmux-peek-capture-pane-async)
                 (lambda (_callback opts)
                   (setq capture-call opts)
                   :capture-handle)))
        (should (eq (tmux-peek-session-list-view "main") :pane-handle))
        (should (equal pane-call '(:socket-name "peek" :target "main")))
        (should (equal capture-call
                       '(:socket-name "peek" :target "%1" :tail-lines 20)))))))

(ert-deftest tmux-peek-session-list-render-content-uses-current-buffer ()
  (let ((tmux-peek-session-list-tail-lines 10))
    (with-temp-buffer
      (tmux-peek-session-list-mode)
      (tmux-peek-session-list--render-content
       "main" '(:ok t :value "line1\nline2\n"))
      (should (equal (tmux-peek-session-list--tail-session) "main"))
      (should (null header-line-format))
      (should (string-match-p "b back to sessions" (buffer-string)))
      (should (string-match-p "tmux session: main" (buffer-string)))
      (should (string-match-p "line2" (buffer-string))))))

(ert-deftest tmux-peek-session-list-refresh-recaptures-tail-view ()
  (with-temp-buffer
    (tmux-peek-session-list-mode)
    (let ((tmux-peek-session-list--opts '(:socket-name "peek"))
          pane-call)
      (tmux-peek-session-list--set-tail-state "main")
      (cl-letf (((symbol-function 'tmux-peek-list-panes-async)
                 (lambda (_callback opts)
                   (setq pane-call opts)
                   :pane-handle)))
        (should (eq (tmux-peek-session-list-refresh) :pane-handle))
        (should (equal pane-call '(:socket-name "peek" :target "main")))))))

(ert-deftest tmux-peek-session-list-view-reuses-tail-session ()
  (with-temp-buffer
    (tmux-peek-session-list-mode)
    (let (pane-call)
      (tmux-peek-session-list--set-tail-state "main")
      (cl-letf (((symbol-function 'tmux-peek-list-panes-async)
                 (lambda (_callback opts)
                   (setq pane-call opts)
                   :pane-handle)))
        (should (eq (tmux-peek-session-list-view) :pane-handle))
        (should (equal pane-call '(:target "main")))))))

(ert-deftest tmux-peek-session-list-back-refreshes-session-list ()
  (with-temp-buffer
    (tmux-peek-session-list-mode)
    (let (called)
      (tmux-peek-session-list--set-tail-state "main")
      (cl-letf (((symbol-function 'tmux-peek-list-sessions-async)
                 (lambda (_callback _opts)
                   (setq called t)
                   :handle)))
        (should (eq (tmux-peek-session-list-back) :handle))
        (should (null (tmux-peek-session-list--tail-session)))
        (should called)))))

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
