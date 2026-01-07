;;; bootstrap.el --- Bootstrap packages & tree-sitter -*- lexical-binding: t; -*-

;; Run in batch:
;;   emacs --batch -l ~/.emacs.d/bootstrap.el
;;
;; Or interactively:
;;   M-x modern-bootstrap

(require 'package)

(defgroup modern-emacs nil
  "Modern, batteries-included Emacs configuration."
  :group 'convenience)

(defcustom modern-bootstrap-install-optional t
  "Whether to install optional (nice-to-have) packages during bootstrap."
  :type 'boolean
  :group 'modern-emacs)

(defcustom modern-bootstrap-install-treesit t
  "Whether to install Tree-sitter grammars during bootstrap."
  :type 'boolean
  :group 'modern-emacs)

(defun modern--env-true-p (name)
  (let ((v (getenv name)))
    (and v (not (member (downcase v) '("" "0" "false" "no" "off"))))))

(when (modern--env-true-p "MODERN_EMACS_BOOTSTRAP_NO_OPTIONAL")
  (setq modern-bootstrap-install-optional nil))
(when (modern--env-true-p "MODERN_EMACS_BOOTSTRAP_NO_TREESIT")
  (setq modern-bootstrap-install-treesit nil))

(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))
(setq package-archive-priorities
      '(("gnu" . 20)
        ("nongnu" . 10)
        ("melpa" . 0)))

;; Prefer newer TLS settings, and avoid local proxy surprises.
(setq url-privacy-level 'high)

(package-initialize)

(defvar modern--bootstrap-refreshed nil)
(defun modern--package-refresh-contents-once ()
  (unless modern--bootstrap-refreshed
    (message "[modern] Refreshing package archives…")
    (package-refresh-contents)
    (setq modern--bootstrap-refreshed t)))

(defun modern--ensure-package (pkg)
  "Ensure PKG is installed; return non-nil if installed now or already present."
  (condition-case err
      (progn
        (unless (package-installed-p pkg)
          (modern--package-refresh-contents-once)
          (message "[modern] Installing %s…" pkg)
          (package-install pkg))
        t)
    (error
     (message "[modern] WARN: failed installing %s: %s" pkg (error-message-string err))
     nil)))

(defun modern-bootstrap-packages ()
  "Install the required (and optionally optional) packages."
  (interactive)
  ;; Keys/signatures: keep package installs reliable.
  (modern--ensure-package 'gnu-elpa-keyring-update)

  ;; Core UX stack (GNU/NonGNU ELPA; stable).
  (dolist (pkg '(use-package
                 which-key
                 vertico
                 orderless
                 marginalia
                 consult
                 embark
                 corfu
                 cape
                 yasnippet
                 yasnippet-snippets
                 go-mode
                 rust-mode
                 yaml-mode
                 dockerfile-mode
                 rainbow-delimiters
                 magit
                 diff-hl
                 editorconfig
                 jinx
                 visual-fill-column
                 markdown-mode
                 org-modern
                 exec-path-from-shell
                 eat
                 gptel))
    (modern--ensure-package pkg))

  (when modern-bootstrap-install-optional
    ;; Optional eye-candy / extras. If any of these fail, the config still works.
    (dolist (pkg '(terraform-mode
                   nerd-icons nerd-icons-completion nerd-icons-dired))
      (modern--ensure-package pkg))))

;; Tree-sitter grammars (built-in in Emacs 29+).
(defun modern-bootstrap-treesit-grammars ()
  "Install a curated set of Tree-sitter grammars if supported."
  (interactive)
  (when (and modern-bootstrap-install-treesit (fboundp 'treesit-install-language-grammar))
    (require 'treesit)
    ;; Sources: conservative, canonical repos.
    (setq treesit-language-source-alist
          '((bash . ("https://github.com/tree-sitter/tree-sitter-bash"))
            (c . ("https://github.com/tree-sitter/tree-sitter-c"))
            (cpp . ("https://github.com/tree-sitter/tree-sitter-cpp"))
            (css . ("https://github.com/tree-sitter/tree-sitter-css"))
            (dockerfile . ("https://github.com/camdencheek/tree-sitter-dockerfile"))
            (go . ("https://github.com/tree-sitter/tree-sitter-go"))
            (gomod . ("https://github.com/camdencheek/tree-sitter-go-mod"))
            (html . ("https://github.com/tree-sitter/tree-sitter-html"))
            (javascript . ("https://github.com/tree-sitter/tree-sitter-javascript"))
            (json . ("https://github.com/tree-sitter/tree-sitter-json"))
            (python . ("https://github.com/tree-sitter/tree-sitter-python"))
            (rust . ("https://github.com/tree-sitter/tree-sitter-rust"))
            (toml . ("https://github.com/tree-sitter/tree-sitter-toml"))
            (tsx . ("https://github.com/tree-sitter/tree-sitter-typescript" "master" "tsx/src"))
            (typescript . ("https://github.com/tree-sitter/tree-sitter-typescript" "master" "typescript/src"))
            (yaml . ("https://github.com/tree-sitter/tree-sitter-yaml"))
            (hcl . ("https://github.com/tree-sitter-grammars/tree-sitter-hcl"))))
    (dolist (lang '(bash c cpp css dockerfile go gomod html javascript json python rust toml typescript tsx yaml hcl))
      (condition-case err
          (progn
            (message "[modern] Installing tree-sitter grammar: %s…" lang)
            (treesit-install-language-grammar lang))
        (error
         (message "[modern] WARN: failed installing grammar %s: %s" lang (error-message-string err))))))
  (unless (fboundp 'treesit-install-language-grammar)
    (message "[modern] Tree-sitter install not supported in this Emacs build.")))

(defun modern-bootstrap ()
  "Install packages (and tree-sitter grammars) for the Modern Emacs config."
  (interactive)
  (modern-bootstrap-packages)
  (modern-bootstrap-treesit-grammars)
  (message "[modern] Bootstrap complete."))

;; If loaded in batch mode, run automatically.
(when noninteractive
  (modern-bootstrap))

;;; bootstrap.el ends here
