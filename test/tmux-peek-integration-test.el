;;; tmux-peek-integration-test.el --- tmux integration tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'seq)
(require 'tmux-peek)

(defconst tmux-peek-test--socket "tmux-peek-test")
(defconst tmux-peek-test--session "tmux-peek-test-session")
(defconst tmux-peek-test--window "main")

(defun tmux-peek-test--tmux (&rest args)
  "Run tmux with ARGS on the test socket."
  (with-temp-buffer
    (let ((status (apply #'call-process
                         "tmux" nil (current-buffer) nil
                         "-L" tmux-peek-test--socket args)))
      (list status (buffer-substring-no-properties (point-min) (point-max))))))

(defun tmux-peek-test--tmux-ok (&rest args)
  "Run tmux with ARGS and fail unless it exits successfully."
  (pcase-let ((`(,status ,output) (apply #'tmux-peek-test--tmux args)))
    (unless (zerop status)
      (ert-fail (format "tmux failed (%s): %s" status output)))
    output))

(defun tmux-peek-test--cleanup ()
  "Best-effort cleanup for the dedicated tmux test socket."
  (tmux-peek-test--tmux "kill-session" "-t" tmux-peek-test--session))

(defun tmux-peek-test--setup ()
  "Create a tmux test session with two panes."
  (unless (executable-find "tmux")
    (ert-skip "tmux executable not found"))
  (tmux-peek-test--cleanup)
  (tmux-peek-test--tmux-ok
   "new-session" "-d" "-s" tmux-peek-test--session
   "-n" tmux-peek-test--window "printf ready; while true; do sleep 1; done")
  (tmux-peek-test--tmux-ok
   "set-environment" "-t" tmux-peek-test--session
   "TMUX_PEEK_TEST_ENV" "ok")
  (tmux-peek-test--tmux-ok
   "set-buffer" "-b" "tmux-peek-test-buffer" "buffer-text")
  (tmux-peek-test--tmux-ok
   "split-window" "-d" "-t" (concat tmux-peek-test--session ":" tmux-peek-test--window)
   "printf second; while true; do sleep 1; done"))

(defun tmux-peek-test--wait (starter)
  "Run STARTER and wait for its async result."
  (let ((done nil)
        result)
    (funcall starter
             (lambda (value)
               (setq result value)
               (setq done t)))
    (let ((deadline (+ (float-time) 5.0)))
      (while (and (not done) (< (float-time) deadline))
        (accept-process-output nil 0.01)))
    (unless done
      (ert-fail "Timed out waiting for async callback"))
    result))

(defmacro tmux-peek-test--with-session (&rest body)
  "Run BODY with a dedicated tmux test session."
  (declare (indent 0))
  `(unwind-protect
       (progn
         (tmux-peek-test--setup)
         ,@body)
     (tmux-peek-test--cleanup)))

(ert-deftest tmux-peek-integration-list-and-capture ()
  (tmux-peek-test--with-session
    (let* ((session-opts (list :socket-name tmux-peek-test--socket))
           (pane-opts (list :socket-name tmux-peek-test--socket
                            :target (concat tmux-peek-test--session
                                            ":" tmux-peek-test--window)))
           (sessions
            (tmux-peek-test--wait
             (lambda (callback)
               (tmux-peek-list-sessions-async callback session-opts))))
           (panes
            (tmux-peek-test--wait
             (lambda (callback)
               (tmux-peek-list-panes-async callback pane-opts))))
           (first-pane (plist-get (car (plist-get panes :value)) :pane-id))
           (capture
            (tmux-peek-test--wait
             (lambda (callback)
               (tmux-peek-capture-pane-async
                callback
                (list :socket-name tmux-peek-test--socket
                      :target first-pane
                      :tail-lines 5))))))
      (should (plist-get sessions :ok))
      (should (equal (plist-get (car (plist-get sessions :value)) :name)
                     tmux-peek-test--session))
      (should (plist-get panes :ok))
      (should (= (length (plist-get panes :value)) 2))
      (should (plist-get capture :ok))
      (should (string-match-p "ready\\|second" (plist-get capture :value))))))

(ert-deftest tmux-peek-integration-kill-pane-only ()
  (tmux-peek-test--with-session
    (let* ((pane-opts (list :socket-name tmux-peek-test--socket
                            :target (concat tmux-peek-test--session
                                            ":" tmux-peek-test--window)))
           (panes-before
            (tmux-peek-test--wait
             (lambda (callback)
               (tmux-peek-list-panes-async callback pane-opts))))
           (target (plist-get (cadr (plist-get panes-before :value)) :pane-id))
           (kill-result
            (tmux-peek-test--wait
             (lambda (callback)
               (tmux-peek-kill-pane-async
                target callback
                (list :socket-name tmux-peek-test--socket)))))
           (panes-after
            (tmux-peek-test--wait
             (lambda (callback)
               (tmux-peek-list-panes-async callback pane-opts)))))
      (should (= (length (plist-get panes-before :value)) 2))
      (should (plist-get kill-result :ok))
      (should (equal (plist-get kill-result :value) t))
      (should (= (length (plist-get panes-after :value)) 1)))))

(ert-deftest tmux-peek-integration-show-options-and-environment ()
  (tmux-peek-test--with-session
    (let* ((opts (list :socket-name tmux-peek-test--socket
                       :target tmux-peek-test--session))
           (options
            (tmux-peek-test--wait
             (lambda (callback)
               (tmux-peek-show-options-async
                callback
                (list :socket-name tmux-peek-test--socket
                      :global t
                      :option "status")))))
           (environment
            (tmux-peek-test--wait
             (lambda (callback)
               (tmux-peek-show-environment-async
                callback
                (append opts (list :variable "TMUX_PEEK_TEST_ENV")))))))
      (should (plist-get options :ok))
      (should (assoc "status" (plist-get options :value)))
      (should (plist-get environment :ok))
      (should (equal (cdr (assoc "TMUX_PEEK_TEST_ENV"
                                 (plist-get environment :value)))
                     "ok")))))

(ert-deftest tmux-peek-integration-list-buffers ()
  (tmux-peek-test--with-session
    (let* ((buffers
           (tmux-peek-test--wait
            (lambda (callback)
              (tmux-peek-list-buffers-async
               callback
               (list :socket-name tmux-peek-test--socket)))))
           (buffer-text
            (tmux-peek-test--wait
             (lambda (callback)
               (tmux-peek-show-buffer-async
                callback
                (list :socket-name tmux-peek-test--socket
                      :buffer-name "tmux-peek-test-buffer"))))))
      (should (plist-get buffers :ok))
      (should (seq-some
               (lambda (buffer)
                 (and (equal (plist-get buffer :name) "tmux-peek-test-buffer")
                      (equal (plist-get buffer :sample) "buffer-text")))
               (plist-get buffers :value)))
      (should (plist-get buffer-text :ok))
      (should (equal (plist-get buffer-text :value) "buffer-text")))))

(ert-deftest tmux-peek-integration-server-and-target-helpers ()
  (tmux-peek-test--with-session
    (let* ((opts (list :socket-name tmux-peek-test--socket))
           (target (concat tmux-peek-test--session ":" tmux-peek-test--window))
           (server-running
            (tmux-peek-test--wait
             (lambda (callback)
               (tmux-peek-server-running-p-async callback opts))))
           (target-exists
            (tmux-peek-test--wait
             (lambda (callback)
               (tmux-peek-target-exists-p-async target callback opts))))
           (target-missing
            (tmux-peek-test--wait
             (lambda (callback)
               (tmux-peek-target-exists-p-async
                "%999999" callback opts))))
           (message
            (tmux-peek-test--wait
             (lambda (callback)
               (tmux-peek-display-message-async
                "#{session_name}" callback
                (append opts (list :target target)))))))
      (should (equal (plist-get server-running :value) t))
      (should (equal (plist-get target-exists :value) t))
      (should (equal (plist-get target-missing :value) nil))
      (should (equal (plist-get message :value) tmux-peek-test--session)))))

(provide 'tmux-peek-integration-test)
;;; tmux-peek-integration-test.el ends here
