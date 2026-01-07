;;; init.el --- Modern, forgiving Emacs config -*- lexical-binding: t; -*-

;; This config aims to be:
;; - Modern (Vertico/Consult/Corfu, Tree-sitter, Eglot, Jinx, gptel)
;; - Stable (prefer GNU ELPA / NonGNU ELPA; MELPA only for optional extras)
;; - Forgiving (works even if optional deps are missing)
;;
;; Local customizations:
;; - Put personal overrides in ~/.emacs.d/init-local.el (loaded if present)
;; - Customize UI settings via M-x customize; they go to ~/.emacs.d/custom.el

(setq custom-file (locate-user-emacs-file "custom.el"))
(when (file-exists-p custom-file)
  (load custom-file 'noerror))

(defvar modern-init-local-file (locate-user-emacs-file "init-local.el"))
;; Loaded at end of init to allow using `use-package` etc.

;; ---------------------------------------------------------------------------
;; Sensible defaults
;; ---------------------------------------------------------------------------

(setq inhibit-startup-screen t
      initial-scratch-message nil
      make-backup-files t
      create-lockfiles nil
      auto-save-default t
      history-length 500
      use-short-answers t
      confirm-nonexistent-file-or-buffer nil
      sentence-end-double-space nil
      require-final-newline t
      scroll-conservatively 101
      scroll-margin 3
      scroll-preserve-screen-position t
      mouse-wheel-progressive-speed nil
      mouse-wheel-follow-mouse t
      fast-but-imprecise-scrolling t
      tab-always-indent 'complete
      enable-recursive-minibuffers t)

(setq-default indent-tabs-mode nil
              tab-width 4
              fill-column 100)

(global-auto-revert-mode 1)
(save-place-mode 1)
(savehist-mode 1)
(recentf-mode 1)
(setq recentf-max-saved-items 500)

;; Prefer the modern buffer list.
(global-set-key (kbd "C-x C-b") #'ibuffer)

;; Keep auto-saves/backups out of the working tree.
(let ((autosave-dir (locate-user-emacs-file "var/autosave/"))
      (backup-dir   (locate-user-emacs-file "var/backup/")))
  (make-directory autosave-dir t)
  (make-directory backup-dir t)
  (setq auto-save-file-name-transforms `((".*" ,autosave-dir t))
        backup-directory-alist `(("." . ,backup-dir))))

(column-number-mode 1)
(size-indication-mode 1)
(global-hl-line-mode 1)
(show-paren-mode 1)
(electric-pair-mode 1)
(when (fboundp 'global-hl-todo-mode)
  (global-hl-todo-mode 1))

;; A nicer default UI (works in both GUI and terminal).
(setq frame-title-format '("%b — Emacs")
      visible-bell nil)
(when (fboundp 'pixel-scroll-precision-mode)
  (pixel-scroll-precision-mode 1))

;; Line numbers in code, not in terminals.
(add-hook 'prog-mode-hook #'display-line-numbers-mode)
(dolist (hook '(term-mode-hook eat-mode-hook eshell-mode-hook shell-mode-hook))
  (add-hook hook (lambda () (display-line-numbers-mode -1))))

;; macOS: make ⌥ act like Meta (common in terminals too).
(when (and (eq system-type 'darwin) (boundp 'mac-option-modifier))
  (setq mac-option-modifier 'meta
        mac-command-modifier 'super
        mac-right-option-modifier 'none))

;; ---------------------------------------------------------------------------
;; Packages (GNU ELPA + NonGNU ELPA, optional MELPA extras)
;; ---------------------------------------------------------------------------

(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))
(setq package-archive-priorities
      '(("gnu" . 20)
        ("nongnu" . 10)
        ("melpa" . 0)))

(package-initialize)

(defvar modern--pkg-refreshed nil)
(defun modern--package-refresh-contents-once ()
  (unless modern--pkg-refreshed
    (package-refresh-contents)
    (setq modern--pkg-refreshed t)))

(defun modern--ensure-package (pkg)
  (unless (package-installed-p pkg)
    (modern--package-refresh-contents-once)
    (package-install pkg)))

;; Bootstrap use-package on first launch so the rest of init works.
(modern--ensure-package 'gnu-elpa-keyring-update)
(modern--ensure-package 'use-package)
(require 'use-package)
(setq use-package-always-ensure t
      use-package-always-defer t
      use-package-expand-minimally t)

;; Help Emacs.app pick up your PATH (e.g., brew, mise, asdf).
(use-package exec-path-from-shell
  :if (and (eq system-type 'darwin) (display-graphic-p))
  :demand t
  :config
  (exec-path-from-shell-initialize)
  (exec-path-from-shell-copy-envs '("PATH" "MANPATH" "SSH_AUTH_SOCK" "GPG_TTY"
                                   "OPENAI_API_KEY" "ANTHROPIC_API_KEY")))

;; ---------------------------------------------------------------------------
;; Completion & discovery (Vertico/Consult/Corfu)
;; ---------------------------------------------------------------------------

(use-package which-key
  :demand t
  :custom
  (which-key-idle-delay 0.35)
  (which-key-idle-secondary-delay 0.05)
  :config
  (which-key-mode 1))

(use-package vertico
  :demand t
  :config
  (vertico-mode 1))

(use-package orderless
  :demand t
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles partial-completion)))))

(use-package marginalia
  :demand t
  :config
  (marginalia-mode 1))

(use-package consult
  :bind (("C-s" . consult-line)
         ("C-x b" . consult-buffer)
         ("M-y" . consult-yank-pop)
         ("C-c r" . consult-ripgrep)
         ("C-c i" . consult-imenu)
         ("C-c k" . consult-keep-lines)
         ("C-x p b" . consult-project-buffer)))

;; A small, discoverable project prefix.
(define-prefix-command 'modern-project-map)
(global-set-key (kbd "C-c p") modern-project-map)
(define-key modern-project-map (kbd "p") #'project-switch-project)
(define-key modern-project-map (kbd "f") #'project-find-file)
(define-key modern-project-map (kbd "d") #'project-find-dir)
(define-key modern-project-map (kbd "b") #'consult-project-buffer)
(define-key modern-project-map (kbd "g") #'consult-ripgrep)
(define-key modern-project-map (kbd "s") #'project-shell)

(use-package embark
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim)
         ("C-h B" . embark-bindings))
  :init
  (setq prefix-help-command #'embark-prefix-help-command))

(use-package corfu
  :demand t
  :custom
  (corfu-auto t)
  (corfu-auto-prefix 2)
  (corfu-auto-delay 0.08)
  (corfu-cycle t)
  (corfu-preselect-first t)
  (corfu-quit-no-match 'separator)
  :config
  (global-corfu-mode 1)
  (when (fboundp 'corfu-popupinfo-mode)
    (corfu-popupinfo-mode 1)))

(use-package cape
  :after corfu
  :config
  ;; Add a few useful completion-at-point backends.
  (add-to-list 'completion-at-point-functions #'cape-file)
  (add-to-list 'completion-at-point-functions #'cape-dabbrev))

;; Optional icons (works best with Nerd Fonts).
(use-package nerd-icons
  :ensure nil
  :if (and (display-graphic-p) (require 'nerd-icons nil t)))
(use-package nerd-icons-completion
  :ensure nil
  :after marginalia
  :if (and (display-graphic-p) (require 'nerd-icons-completion nil t))
  :demand t
  :config
  (nerd-icons-completion-mode 1))
(use-package nerd-icons-dired
  :ensure nil
  :hook (dired-mode . nerd-icons-dired-mode)
  :if (and (display-graphic-p) (require 'nerd-icons-dired nil t)))

;; ---------------------------------------------------------------------------
;; Editing niceties
;; ---------------------------------------------------------------------------

(use-package avy
  :bind (("M-j" . avy-goto-char-timer)))

(use-package expand-region
  :bind (("C-=" . er/expand-region)))

(use-package multiple-cursors
  :bind (("C->" . mc/mark-next-like-this)
         ("C-<" . mc/mark-previous-like-this)
         ("C-c C-<" . mc/mark-all-like-this)))

(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

(use-package yasnippet
  :demand t
  :config
  (yas-global-mode 1))

(use-package yasnippet-snippets
  :after yasnippet)

(use-package editorconfig
  :demand t
  :config
  (editorconfig-mode 1))

;; Language modes (stable major modes; Tree-sitter remaps when available).
(use-package go-mode
  :mode "\\.go\\'")
(use-package rust-mode
  :mode "\\.rs\\'")
(use-package yaml-mode
  :mode "\\.ya?ml\\'")
(use-package dockerfile-mode
  :mode ("\\'Dockerfile\\'" . dockerfile-mode))
(use-package terraform-mode
  :ensure nil
  :mode ("\\.tf\\'" "\\.tfvars\\'"))

;; Modern spell-check (requires `enchant` on macOS via Homebrew).
(use-package jinx
  :hook ((text-mode . jinx-mode)
         (prog-mode . jinx-mode))
  :bind (("C-c s" . jinx-correct)
         ("C-c S" . jinx-languages)))

;; ---------------------------------------------------------------------------
;; Git
;; ---------------------------------------------------------------------------

(use-package magit
  :bind (("C-x g" . magit-status)))

(use-package diff-hl
  :hook ((prog-mode . diff-hl-mode)
         (text-mode . diff-hl-mode)
         (dired-mode . diff-hl-dired-mode))
  :config
  (diff-hl-flydiff-mode 1))

;; ---------------------------------------------------------------------------
;; Terminal inside Emacs (EAT)
;; ---------------------------------------------------------------------------

(use-package eat
  :bind (("C-c t" . eat)))

;; ---------------------------------------------------------------------------
;; Tree-sitter & LSP (Eglot)
;; ---------------------------------------------------------------------------

(defun modern--treesit-remap (from to lang)
  (when (and (fboundp 'treesit-ready-p)
             (fboundp to)
             (treesit-ready-p lang t))
    (add-to-list 'major-mode-remap-alist (cons from to))))

(when (require 'treesit nil t)
  (modern--treesit-remap 'bash-mode 'bash-ts-mode 'bash)
  (modern--treesit-remap 'c-mode 'c-ts-mode 'c)
  (modern--treesit-remap 'c++-mode 'c++-ts-mode 'cpp)
  (modern--treesit-remap 'css-mode 'css-ts-mode 'css)
  (modern--treesit-remap 'python-mode 'python-ts-mode 'python)
  (modern--treesit-remap 'js-mode 'js-ts-mode 'javascript)
  (modern--treesit-remap 'js-json-mode 'json-ts-mode 'json)
  (modern--treesit-remap 'typescript-mode 'typescript-ts-mode 'typescript)
  (modern--treesit-remap 'tsx-mode 'tsx-ts-mode 'tsx)
  (modern--treesit-remap 'go-mode 'go-ts-mode 'go)
  (modern--treesit-remap 'rust-mode 'rust-ts-mode 'rust)
  (modern--treesit-remap 'toml-mode 'toml-ts-mode 'toml)
  (modern--treesit-remap 'yaml-mode 'yaml-ts-mode 'yaml)
  (modern--treesit-remap 'terraform-mode 'hcl-ts-mode 'hcl))

(defun modern/eglot-format-buffer ()
  (interactive)
  (cond
   ((fboundp 'eglot-format-buffer) (call-interactively 'eglot-format-buffer))
   ((fboundp 'eglot-format) (call-interactively 'eglot-format))
   (t (user-error "Eglot formatting not available"))))

(use-package eglot
  :ensure nil
  :hook ((go-mode go-ts-mode
                  python-mode python-ts-mode
                  js-mode js-ts-mode
                  typescript-mode typescript-ts-mode
                  rust-mode rust-ts-mode
                  bash-mode bash-ts-mode
                  yaml-mode yaml-ts-mode
                  terraform-mode hcl-ts-mode
                  dockerfile-mode dockerfile-ts-mode) . eglot-ensure)
  :bind (:map eglot-mode-map
              ("C-c f" . modern/eglot-format-buffer))
  :custom
  (eglot-autoshutdown t)
  (eglot-events-buffer-size 0)
  :config
  ;; Prefer external language servers if installed (the setup script installs these).
  (add-to-list 'eglot-server-programs
               '((python-mode python-ts-mode) . ("pyright-langserver" "--stdio")))
  (add-to-list 'eglot-server-programs
               '((go-mode go-ts-mode) . ("gopls")))
  (add-to-list 'eglot-server-programs
               '((rust-mode rust-ts-mode) . ("rust-analyzer")))
  (add-to-list 'eglot-server-programs
               '((bash-mode bash-ts-mode) . ("bash-language-server" "start")))
  (add-to-list 'eglot-server-programs
               '((yaml-mode yaml-ts-mode) . ("yaml-language-server" "--stdio")))
  (add-to-list 'eglot-server-programs
               '((dockerfile-mode dockerfile-ts-mode) . ("docker-langserver" "--stdio")))
  (add-to-list 'eglot-server-programs
               '((terraform-mode hcl-ts-mode) . ("terraform-ls" "serve"))))

;; ---------------------------------------------------------------------------
;; Org & Markdown (nice-looking notes)
;; ---------------------------------------------------------------------------

(use-package visual-fill-column
  :hook ((org-mode markdown-mode) . visual-fill-column-mode)
  :custom
  (visual-fill-column-width 100)
  (visual-fill-column-center-text t))

(use-package org
  :ensure nil
  :custom
  (org-hide-emphasis-markers t)
  (org-ellipsis " ▾")
  (org-startup-indented t)
  (org-startup-with-inline-images t)
  :bind (("C-c a" . org-agenda)
         ("C-c c" . org-capture)))

(use-package org-modern
  :hook (org-mode . org-modern-mode)
  :custom
  (org-modern-star '("◉" "○" "✸" "✿"))
  (org-modern-list '((?+ . "•") (?- . "–") (?* . "‣"))))

(use-package markdown-mode
  :mode (("\\.md\\'" . markdown-mode)
         ("\\.markdown\\'" . markdown-mode)))

;; ---------------------------------------------------------------------------
;; AI (gptel)
;; ---------------------------------------------------------------------------

(use-package gptel
  :commands (gptel gptel-menu gptel-send gptel-rewrite)
  :bind (("C-c A" . gptel-menu)
         ("C-c G" . gptel))
  :config
  ;; Prefer environment variables (don’t store keys in init.el).
  (let ((openai (or (getenv "OPENAI_API_KEY") (getenv "OPENAI_KEY")))
        (anthropic (getenv "ANTHROPIC_API_KEY")))
    (cond
     (openai
      (setq gptel-api-key (lambda () openai)))
     (anthropic
      (when (fboundp 'gptel-make-anthropic)
        (setq gptel-backend (gptel-make-anthropic "Anthropic"
                              :key (lambda () anthropic)
                              :stream t))))))
  ;; Default to Org for readable chats.
  (setq gptel-default-mode 'org-mode))

;; ---------------------------------------------------------------------------
;; Fonts & theme (beautiful, modern defaults)
;; ---------------------------------------------------------------------------

(defun modern--font-available-p (name)
  (when (display-graphic-p)
    (find-font (font-spec :name name))))

(defun modern-setup-fonts ()
  (when (display-graphic-p)
    (let ((mono "JetBrainsMono Nerd Font")
          (var "Inter"))
      (when (modern--font-available-p mono)
        (set-face-attribute 'default nil :family mono :height 140))
      (when (modern--font-available-p var)
        (set-face-attribute 'variable-pitch nil :family var :height 150))
      (setq-default line-spacing 0.12))))

(add-hook 'after-init-hook #'modern-setup-fonts)

;; Built-in, high-quality themes.
(use-package modus-themes
  :ensure nil
  :demand t
  :custom
  (modus-themes-italic-constructs t)
  (modus-themes-bold-constructs t)
  (modus-themes-mixed-fonts t)
  (modus-themes-variable-pitch-ui t)
  :config
  (load-theme 'modus-vivendi t))

;; Finally, load your personal overrides.
(when (file-exists-p modern-init-local-file)
  (load modern-init-local-file 'noerror))

;;; init.el ends here
