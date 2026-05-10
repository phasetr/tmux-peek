;;; tmux-peek-session-list.el --- Session list UI for tmux-peek -*- lexical-binding: t; -*-

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

;; Tabulated session list for inspecting and explicitly killing tmux sessions.

;;; Code:

(require 'tabulated-list)
(require 'tmux-peek-api)

(defcustom tmux-peek-session-list-buffer-name "*tmux-peek sessions*"
  "Buffer name for the tmux-peek session list."
  :type 'string
  :group 'tmux-peek)

(defcustom tmux-peek-session-list-tail-lines 80
  "Number of tail lines to capture when viewing a session."
  :type 'integer
  :group 'tmux-peek)

(defvar-local tmux-peek-session-list--opts nil)
(defvar-local tmux-peek-session-list--last-result nil)
(defvar-local tmux-peek-session-list--state nil)

(defconst tmux-peek-session-list--help-text
  "Keys: RET/v/t view tail | d/k delete session | g/r refresh | q quit\n\n")

(defconst tmux-peek-session-list--tail-help-text
  "Keys: b back to sessions | g/r refresh tail | d/k delete session | q quit\n\n")

(defvar tmux-peek-session-list-mode-map (make-sparse-keymap)
  "Keymap for `tmux-peek-session-list-mode'.")

(defun tmux-peek-session-list--setup-keymap ()
  "Install tmux-peek session list bindings into the mode keymap."
  (set-keymap-parent tmux-peek-session-list-mode-map tabulated-list-mode-map)
  (define-key tmux-peek-session-list-mode-map (kbd "g")
              #'tmux-peek-session-list-refresh)
  (define-key tmux-peek-session-list-mode-map (kbd "r")
              #'tmux-peek-session-list-refresh)
  (define-key tmux-peek-session-list-mode-map (kbd "RET")
              #'tmux-peek-session-list-view)
  (define-key tmux-peek-session-list-mode-map (kbd "v")
              #'tmux-peek-session-list-view)
  (define-key tmux-peek-session-list-mode-map (kbd "t")
              #'tmux-peek-session-list-view)
  (define-key tmux-peek-session-list-mode-map (kbd "d")
              #'tmux-peek-session-list-kill)
  (define-key tmux-peek-session-list-mode-map (kbd "k")
              #'tmux-peek-session-list-kill)
  (define-key tmux-peek-session-list-mode-map (kbd "b")
              #'tmux-peek-session-list-back)
  (define-key tmux-peek-session-list-mode-map (kbd "q") #'quit-window))

(tmux-peek-session-list--setup-keymap)

(define-derived-mode tmux-peek-session-list-mode tabulated-list-mode
  "tmux-peek-sessions"
  "Major mode for inspecting and killing tmux sessions."
  (setq tabulated-list-format
        [("Name" 24 t)
         ("Id" 8 t)
         ("Windows" 8 t)
         ("Attached" 8 t)
         ("Created" 12 t)])
  (setq tabulated-list-padding 2)
  (setq tabulated-list-sort-key (cons "Name" nil))
  (tabulated-list-init-header))

(defun tmux-peek-session-list--string (value)
  "Return VALUE as a display string."
  (if value (format "%s" value) ""))

(defun tmux-peek-session-list--entry (session)
  "Return a tabulated-list entry for SESSION."
  (let ((name (tmux-peek-session-list--string (plist-get session :name))))
    (list name
          (vector
           name
           (tmux-peek-session-list--string (plist-get session :id))
           (tmux-peek-session-list--string (plist-get session :windows))
           (if (plist-get session :attached) "yes" "no")
           (tmux-peek-session-list--string (plist-get session :created))))))

(defun tmux-peek-session-list--session-at-point ()
  "Return the session name at point."
  (or (tabulated-list-get-id)
      (user-error "No tmux session on this line")))

(defun tmux-peek-session-list--set-list-state ()
  "Mark the current buffer as showing the session list."
  (setq tmux-peek-session-list--state '(:view list :session nil)))

(defun tmux-peek-session-list--set-tail-state (session)
  "Mark the current buffer as showing tail content for SESSION."
  (setq tmux-peek-session-list--state
        (list :view 'tail :session session)))

(defun tmux-peek-session-list--tail-session ()
  "Return the session shown by the current tail view, or nil."
  (when (eq (plist-get tmux-peek-session-list--state :view) 'tail)
    (plist-get tmux-peek-session-list--state :session)))

(defun tmux-peek-session-list--with-live-buffer (buffer function)
  "Call FUNCTION in BUFFER when BUFFER is still live."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (funcall function))))

(defun tmux-peek-session-list--goto-body ()
  "Move point to the first content line after the in-buffer help."
  (goto-char (point-min))
  (forward-line 2))

(defun tmux-peek-session-list--insert-help (text)
  "Insert in-buffer help TEXT at the beginning of the buffer."
  (goto-char (point-min))
  (insert text))

(defun tmux-peek-session-list--list-entries (result)
  "Return tabulated list entries for list-sessions RESULT."
  (when (plist-get result :ok)
    (mapcar #'tmux-peek-session-list--entry
            (plist-get result :value))))

(defun tmux-peek-session-list--insert-tail (session result)
  "Insert captured SESSION content from RESULT."
  (insert tmux-peek-session-list--tail-help-text)
  (insert (format "tmux session: %s\n" session))
  (insert (format "tail lines: %s\n\n" tmux-peek-session-list-tail-lines))
  (if (plist-get result :ok)
      (insert (or (plist-get result :value) ""))
    (insert (format "tmux-peek capture failed: %S\n"
                    (plist-get result :error)))))

(defun tmux-peek-session-list--handle-panes (session opts buffer result)
  "Handle list-panes RESULT for SESSION using OPTS and BUFFER."
  (if (plist-get result :ok)
      (if-let* ((pane (car (plist-get result :value)))
                (pane-id (plist-get pane :pane-id)))
          (tmux-peek-session-list--capture-pane session pane-id opts buffer)
        (message "tmux-peek found no pane in session: %s" session))
    (message "tmux-peek list panes failed: %S"
             (plist-get result :error))))

(defun tmux-peek-session-list--handle-kill (session result)
  "Handle kill-session RESULT for SESSION."
  (setq tmux-peek-session-list--last-result result)
  (if (plist-get result :ok)
      (progn
        (tmux-peek-session-list--set-list-state)
        (message "Killed tmux session: %s" session)
        (tmux-peek-session-list-refresh))
    (message "tmux-peek kill session failed: %S"
             (plist-get result :error))))

(defun tmux-peek-session-list--apply-result (result)
  "Render list-sessions RESULT in the current buffer."
  (tmux-peek-session-list--set-list-state)
  (setq tmux-peek-session-list--last-result result)
  (tabulated-list-init-header)
  (setq tabulated-list-entries (tmux-peek-session-list--list-entries result))
  (tabulated-list-print t)
  (let ((inhibit-read-only t))
    (tmux-peek-session-list--insert-help
     tmux-peek-session-list--help-text))
  (tmux-peek-session-list--goto-body)
  (unless (plist-get result :ok)
    (message "tmux-peek list sessions failed: %S"
             (plist-get result :error))))

(defun tmux-peek-session-list--render-content (session result)
  "Render captured SESSION content from RESULT in the current buffer."
  (let ((inhibit-read-only t))
    (tmux-peek-session-list--set-tail-state session)
    (setq tabulated-list-entries nil)
    (setq header-line-format nil)
    (erase-buffer)
    (tmux-peek-session-list--insert-tail session result))
  (tmux-peek-session-list--goto-body))

(defun tmux-peek-session-list--capture-pane (session pane-id opts buffer)
  "Capture PANE-ID for SESSION with OPTS and render it in BUFFER."
  (tmux-peek-capture-pane-async
   (lambda (result)
     (tmux-peek-session-list--with-live-buffer
      buffer
      (lambda ()
        (tmux-peek-session-list--render-content session result))))
   (append opts
           (list :target pane-id
                 :tail-lines tmux-peek-session-list-tail-lines))))

(defun tmux-peek-session-list-view (&optional session)
  "View one-shot tail-like content for SESSION.
When SESSION is nil, use the session at point."
  (interactive)
  (let ((session (or session
                     (tmux-peek-session-list--tail-session)
                     (tmux-peek-session-list--session-at-point)))
        (opts tmux-peek-session-list--opts)
        (buffer (current-buffer)))
    (tmux-peek-list-panes-async
     (lambda (result)
       (tmux-peek-session-list--with-live-buffer
        buffer
        (lambda ()
          (tmux-peek-session-list--handle-panes
           session opts buffer result))))
     (append opts (list :target session)))))

(defun tmux-peek-session-list-refresh ()
  "Refresh the tmux session list."
  (interactive)
  (if-let* ((session (tmux-peek-session-list--tail-session)))
      (tmux-peek-session-list-view session)
    (let ((buffer (current-buffer))
          (opts tmux-peek-session-list--opts))
      (tmux-peek-list-sessions-async
       (lambda (result)
         (tmux-peek-session-list--with-live-buffer
          buffer
          (lambda ()
            (tmux-peek-session-list--apply-result result))))
       opts))))

(defun tmux-peek-session-list-back ()
  "Return from a session tail view to the session list."
  (interactive)
  (tmux-peek-session-list--set-list-state)
  (tmux-peek-session-list-refresh))

(defun tmux-peek-session-list-kill (&optional session)
  "Kill SESSION, or the tmux session at point when SESSION is nil."
  (interactive)
  (let ((session (or session
                     (tmux-peek-session-list--tail-session)
                     (tmux-peek-session-list--session-at-point)))
        (buffer (current-buffer))
        (opts tmux-peek-session-list--opts))
    (when (y-or-n-p (format "Kill tmux session %s? " session))
      (tmux-peek-kill-session-async
       session
       (lambda (result)
         (tmux-peek-session-list--with-live-buffer
          buffer
          (lambda ()
            (tmux-peek-session-list--handle-kill session result))))
       opts))))

;;;###autoload
(defun tmux-peek-session-list (&optional opts)
  "Open a tmux session list buffer.
OPTS are passed to tmux-peek async commands."
  (interactive)
  (let ((buffer (get-buffer-create tmux-peek-session-list-buffer-name)))
    (with-current-buffer buffer
      (tmux-peek-session-list-mode)
      (setq tmux-peek-session-list--opts opts)
      (tmux-peek-session-list-refresh))
    (pop-to-buffer buffer)))

(provide 'tmux-peek-session-list)
;;; tmux-peek-session-list.el ends here
