;;; tmux-peek-async.el --- Async process helpers for tmux-peek -*- lexical-binding: t; -*-

;; Copyright (C) 2026 phasetr

;; This file is part of tmux-peek.

;; tmux-peek is free software: you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by the
;; Free Software Foundation, either version 3 of the License, or (at your
;; option) any later version.

;; tmux-peek is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
;; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
;; more details.

;; You should have received a copy of the GNU General Public License along
;; with tmux-peek.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Small async executor built on `make-process'.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tmux-peek-error)

(defgroup tmux-peek nil
  "Inspect tmux state from Emacs Lisp."
  :group 'tools)

(defcustom tmux-peek-default-timeout 5.0
  "Default timeout in seconds for tmux-peek async commands."
  :type 'number
  :group 'tmux-peek)

(cl-defstruct (tmux-peek-handle
               (:constructor tmux-peek--make-handle))
  process
  timer
  callback
  stdout-buffer
  stderr-buffer
  command
  done)

(defun tmux-peek--buffer-string (buffer)
  "Return BUFFER contents without text properties."
  (if (buffer-live-p buffer)
      (with-current-buffer buffer
        (buffer-substring-no-properties (point-min) (point-max)))
    ""))

(defun tmux-peek--cleanup-handle (handle)
  "Release timer and buffers associated with HANDLE."
  (when (tmux-peek-handle-timer handle)
    (cancel-timer (tmux-peek-handle-timer handle))
    (setf (tmux-peek-handle-timer handle) nil))
  (dolist (buffer (list (tmux-peek-handle-stdout-buffer handle)
                        (tmux-peek-handle-stderr-buffer handle)))
    (when (buffer-live-p buffer)
      (kill-buffer buffer))))

(defun tmux-peek--finish-handle (handle result)
  "Mark HANDLE done and call its callback with RESULT."
  (unless (tmux-peek-handle-done handle)
    (setf (tmux-peek-handle-done handle) t)
    (tmux-peek--cleanup-handle handle)
    (funcall (tmux-peek-handle-callback handle) result)))

(defun tmux-peek--process-result (handle exit-code)
  "Build a result plist for HANDLE and EXIT-CODE."
  (let* ((stdout (tmux-peek--buffer-string
                  (tmux-peek-handle-stdout-buffer handle)))
         (stderr (tmux-peek--buffer-string
                  (tmux-peek-handle-stderr-buffer handle))))
    (if (zerop exit-code)
        (list :ok t
              :stdout stdout
              :stderr stderr
              :exit-code exit-code
              :command (tmux-peek-handle-command handle))
      (list :ok nil
            :error (tmux-peek--classify-stderr stderr)
            :stdout stdout
            :stderr stderr
            :exit-code exit-code
            :command (tmux-peek-handle-command handle)))))

(defun tmux-peek--timeout-handle (handle)
  "Timeout HANDLE, terminating its process and reporting timeout."
  (unless (tmux-peek-handle-done handle)
    (setf (tmux-peek-handle-done handle) t)
      (let ((process (tmux-peek-handle-process handle))
            (stdout (tmux-peek--buffer-string
                     (tmux-peek-handle-stdout-buffer handle)))
            (stderr (tmux-peek--buffer-string
                     (tmux-peek-handle-stderr-buffer handle))))
        (when (process-live-p process)
          (delete-process process))
      (tmux-peek--cleanup-handle handle)
      (funcall (tmux-peek-handle-callback handle)
               (list :ok nil
                     :error 'tmux-peek-error-timeout
                     :stdout stdout
                     :stderr stderr
                     :exit-code nil
                     :command (tmux-peek-handle-command handle))))))

(defun tmux-peek-cancel (handle)
  "Cancel the process represented by HANDLE."
  (interactive)
  (unless (tmux-peek-handle-p handle)
    (user-error "Not a tmux-peek handle: %S" handle))
  (tmux-peek--timeout-handle handle))

(defun tmux-peek--exec-async (executable args callback &optional opts)
  "Run EXECUTABLE with ARGS and call CALLBACK with a result plist.
OPTS may contain `:timeout'.  Return a `tmux-peek-handle'."
  (unless (functionp callback)
    (signal 'wrong-type-argument (list 'functionp callback)))
  (if-let* ((program (executable-find executable)))
      (let* ((stdout-buffer (generate-new-buffer " *tmux-peek stdout*"))
             (stderr-buffer (generate-new-buffer " *tmux-peek stderr*"))
             (command (cons program args))
             (process-environment (cons "LC_ALL=C" process-environment))
             handle)
        (setq handle
              (tmux-peek--make-handle
               :callback callback
               :stdout-buffer stdout-buffer
               :stderr-buffer stderr-buffer
               :command command))
        (setf
         (tmux-peek-handle-process handle)
         (make-process
          :name "tmux-peek"
          :buffer stdout-buffer
          :stderr stderr-buffer
          :command command
          :noquery t
          :sentinel
          (lambda (process _event)
            (when (memq (process-status process) '(exit signal))
              (tmux-peek--finish-handle
               handle
               (tmux-peek--process-result handle (process-exit-status process)))))))
        (let ((timeout (or (plist-get opts :timeout)
                           tmux-peek-default-timeout)))
          (when (and timeout (> timeout 0))
            (setf (tmux-peek-handle-timer handle)
                  (run-at-time timeout nil #'tmux-peek--timeout-handle handle))))
        handle)
    (let ((handle (tmux-peek--make-handle
                   :callback callback
                   :command (cons executable args)
                   :done t)))
      (run-at-time
       0 nil callback
       (list :ok nil
             :error 'tmux-peek-error-not-found
             :stdout ""
             :stderr (format "Executable not found: %s" executable)
             :exit-code nil
             :command (cons executable args)))
      handle)))

(defun tmux-peek-parallel-async (thunks callback)
  "Run async THUNKS and call CALLBACK when all are complete.
Each thunk is a function that accepts one callback argument and starts an
async operation.  CALLBACK receives results in the same order as THUNKS."
  (let* ((count (length thunks))
         (remaining count)
         (results (make-vector count nil))
         (handles nil))
    (if (zerop count)
        (progn
          (funcall callback nil)
          nil)
      (cl-loop
       for thunk in thunks
       for index from 0
       do (let ((slot index))
            (push
             (funcall
              thunk
              (lambda (result)
                (aset results slot result)
                (setq remaining (1- remaining))
                (when (zerop remaining)
                  (funcall callback (append results nil)))))
             handles)))
      (nreverse handles))))

(provide 'tmux-peek-async)
;;; tmux-peek-async.el ends here
