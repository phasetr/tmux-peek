;;; tmux-peek.el --- Thin async tmux state wrapper -*- lexical-binding: t; -*-

;; Copyright (C) 2026 phasetr

;; Author: phasetr
;; URL: https://github.com/phasetr/tmux-peek
;; Package-Requires: ((emacs "30.1"))
;; Keywords: tools, terminals
;; Version: 0.1.0

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

;; tmux-peek provides small asynchronous helpers for inspecting tmux live
;; state from Emacs Lisp.  It intentionally avoids broad operational wrappers:
;; only `kill-session' is exposed for cleanup of explicitly selected sessions.

;;; Code:

(require 'tmux-peek-error)
(require 'tmux-peek-async)
(require 'tmux-peek-command)
(require 'tmux-peek-parse)
(require 'tmux-peek-api)

(provide 'tmux-peek)
;;; tmux-peek.el ends here
