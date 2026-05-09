;;; tmux-peek-async-test.el --- async executor tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'tmux-peek-async)

(defun tmux-peek-test--wait (starter)
  "Run STARTER and wait for its async result."
  (let ((done nil)
        result)
    (funcall starter
             (lambda (value)
               (setq result value)
               (setq done t)))
    (let ((deadline (+ (float-time) 3.0)))
      (while (and (not done) (< (float-time) deadline))
        (accept-process-output nil 0.01)))
    (unless done
      (ert-fail "Timed out waiting for async callback"))
    result))

(ert-deftest tmux-peek-exec-async-success ()
  (let ((result
         (tmux-peek-test--wait
          (lambda (callback)
            (tmux-peek--exec-async
             "sh" '("-c" "printf ok") callback '(:timeout 1.0))))))
    (should (plist-get result :ok))
    (should (equal (plist-get result :stdout) "ok"))
    (should (= (plist-get result :exit-code) 0))))

(ert-deftest tmux-peek-exec-async-failure ()
  (let ((result
         (tmux-peek-test--wait
          (lambda (callback)
            (tmux-peek--exec-async
             "sh" '("-c" "printf 'no server running' >&2; exit 1")
             callback '(:timeout 1.0))))))
    (should-not (plist-get result :ok))
    (should (eq (plist-get result :error) 'tmux-peek-error-no-server))
    (should (= (plist-get result :exit-code) 1))))

(ert-deftest tmux-peek-exec-async-timeout ()
  (let ((result
         (tmux-peek-test--wait
          (lambda (callback)
            (tmux-peek--exec-async
             "sh" '("-c" "sleep 1") callback '(:timeout 0.05))))))
    (should-not (plist-get result :ok))
    (should (eq (plist-get result :error) 'tmux-peek-error-timeout))))

(ert-deftest tmux-peek-parallel-async-preserves-order ()
  (let ((result
         (tmux-peek-test--wait
          (lambda (callback)
            (tmux-peek-parallel-async
             (list
              (lambda (cb)
                (tmux-peek--exec-async "sh" '("-c" "printf first") cb))
              (lambda (cb)
                (tmux-peek--exec-async "sh" '("-c" "printf second") cb)))
             callback)))))
    (should (equal (mapcar (lambda (item) (plist-get item :stdout)) result)
                   '("first" "second")))))

(provide 'tmux-peek-async-test)
;;; tmux-peek-async-test.el ends here
