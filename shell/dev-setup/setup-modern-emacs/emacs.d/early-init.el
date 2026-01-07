;;; early-init.el --- Modern Emacs early init -*- lexical-binding: t; -*-

;; Keep early-init fast and dependency-free.

;; Don’t auto-enable package.el before init.el sets it up.
(setq package-enable-at-startup nil)

;; Faster startup: be generous during init, then reset after startup.
(setq gc-cons-threshold (* 128 1024 1024)
      gc-cons-percentage 0.6)
(add-hook
 'emacs-startup-hook
 (lambda ()
   (setq gc-cons-threshold (* 32 1024 1024)
         gc-cons-percentage 0.1)))

;; Reduce UI chrome early (works in GUI; harmless in terminal).
(dolist (mode '(menu-bar-mode tool-bar-mode scroll-bar-mode tooltip-mode))
  (when (fboundp mode) (funcall mode -1)))

;; Be less disruptive.
(setq use-dialog-box nil
      ring-bell-function 'ignore)

;; A tiny startup QoL.
(setq inhibit-startup-screen t
      inhibit-startup-message t
      inhibit-startup-echo-area-message user-login-name)

;; Native compilation: keep startup quieter.
(when (boundp 'native-comp-async-report-warnings-errors)
  (setq native-comp-async-report-warnings-errors nil))

;;; early-init.el ends here

