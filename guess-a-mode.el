;;; guess-a-mode.el --- Intelligent major mode detection for buffers -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Laluxx
;; Version: 0.1.0
;; Package-Requires: ((emacs "24.4"))
;; Keywords: convenience, files, languages
;; URL: https://github.com/laluxx/guess-a-mode

;;; Commentary:

;; This package provides intelligent major mode detection for buffers when
;; the standard Emacs auto-mode detection isn't sufficient or when working
;; with buffers that don't have filenames (like fetched URLs, temporary buffers, etc.).
;;
;; DETECTION STRATEGIES (tried in order):
;; 1. Built-in `set-auto-mode' - respects `auto-mode-alist', file associations, and shebangs
;; 2. First-line patterns - matches specific first-line signatures (XML, JSON, etc.)
;; 3. Content-based heuristics - analyzes buffer content using pattern matching
;;
;; SCORING SYSTEM:
;; Each mode has associated patterns and keywords with a score threshold.
;; - Pattern matches: +1 point each (regex patterns like function declarations)
;; - Keyword matches: +0.5 points each (language-specific keywords)
;; - Mode is selected if total score >= threshold
;; - Highest scoring mode wins
;;
;; EXTENSIBILITY:
;; You can add custom heuristics with `guess-a-mode-add-heuristic' or
;; remove existing ones with `guess-a-mode-remove-heuristic'.
;;
;; USAGE:
;; - M-x guess-a-mode

;;; Code:

(require 'cl-lib)

(defgroup guess-a-mode nil
  "Intelligent major mode detection."
  :group 'convenience
  :prefix "guess-a-mode-")

(defcustom guess-a-mode-verbose nil
  "If non-nil, show messages about mode detection process."
  :type 'boolean
  :group 'guess-a-mode)

(defcustom guess-a-mode-fallback-mode 'text-mode
  "Fallback mode when no other mode can be determined."
  :type 'symbol
  :group 'guess-a-mode)

;;; Content-based heuristics

(defvar guess-a-mode-heuristics
  '((json-mode
     :patterns ("^[[:space:]]*[{[]" "\"[^\"]*\"[[:space:]]*:[[:space:]]*")
     :keywords ("null" "true" "false")
     :score-threshold 2)
    
    (yaml-mode
     :patterns ("^[[:space:]]*[a-zA-Z_][^:]*:[[:space:]]*" "^---[[:space:]]*$" "^\\.\\.\\.[[:space:]]*$")
     :keywords ()
     :score-threshold 1)
    
    (python-mode
     :patterns ("^[[:space:]]*def [a-zA-Z_]" "^[[:space:]]*class [a-zA-Z_]" "^[[:space:]]*import " "^[[:space:]]*from .* import")
     :keywords ("def" "class" "import" "if __name__" "print(" "return")
     :score-threshold 2)
    
    (javascript-mode
     :patterns ("function[[:space:]]+[a-zA-Z_]" "var[[:space:]]+[a-zA-Z_]" "let[[:space:]]+[a-zA-Z_]" "const[[:space:]]+[a-zA-Z_]")
     :keywords ("function" "var" "let" "const" "return" "console.log")
     :score-threshold 2)
    
    (css-mode
     :patterns ("[a-zA-Z0-9_-]+[[:space:]]*{" "[a-zA-Z-]+[[:space:]]*:[[:space:]]*[^;]+;" "@[a-zA-Z]+")
     :keywords ()
     :score-threshold 2)
    
    (html-mode
     :patterns ("<[a-zA-Z][^>]*>" "</[a-zA-Z][^>]*>" "<!DOCTYPE" "<!--")
     :keywords ("html" "head" "body" "div" "span")
     :score-threshold 2)
    
    (xml-mode
     :patterns ("<\\?xml" "<[a-zA-Z][^>]*>" "</[a-zA-Z][^>]*>")
     :keywords ()
     :score-threshold 2)
    
    (markdown-mode
     :patterns ("^#+[[:space:]]" "^[[:space:]]*[-*+][[:space:]]" "^[[:space:]]*[0-9]+\\.[[:space:]]" "\\*\\*[^*]+\\*\\*" "\\*[^*]+\\*")
     :keywords ()
     :score-threshold 2)
    
    (sh-mode
     :patterns ("^#!/bin/.*sh" "^[[:space:]]*if[[:space:]]+\\[" "^[[:space:]]*for[[:space:]]+[a-zA-Z_]" "\\$[{a-zA-Z_]")
     :keywords ("echo" "export" "source" "chmod")
     :score-threshold 2)
    
    (sql-mode
     :patterns ("SELECT[[:space:]]+.*FROM" "INSERT[[:space:]]+INTO" "UPDATE[[:space:]]+.*SET" "CREATE[[:space:]]+TABLE")
     :keywords ("SELECT" "FROM" "WHERE" "INSERT" "UPDATE" "DELETE" "CREATE" "ALTER")
     :score-threshold 2)
    
    (dockerfile-mode
     :patterns ("^FROM[[:space:]]+" "^RUN[[:space:]]+" "^COPY[[:space:]]+" "^ADD[[:space:]]+")
     :keywords ("FROM" "RUN" "COPY" "ADD" "EXPOSE" "CMD" "ENTRYPOINT")
     :score-threshold 2)
    
    (conf-mode
     :patterns ("^[[:space:]]*[a-zA-Z_][^=]*=[^=]" "^[[:space:]]*#" "^\\[[^]]+\\]")
     :keywords ()
     :score-threshold 1)
    
    (lisp-mode
     :patterns ("^[[:space:]]*(" "defun[[:space:]]+" "defvar[[:space:]]+" "setq[[:space:]]+")
     :keywords ("defun" "defvar" "setq" "let" "lambda")
     :score-threshold 2)
    
    (emacs-lisp-mode
     :patterns ("^[[:space:]]*(" "defun[[:space:]]+" "defvar[[:space:]]+" "defcustom[[:space:]]+")
     :keywords ("defun" "defvar" "defcustom" "defgroup" "require" "provide")
     :score-threshold 2)
    
    (c-mode
     :patterns ("^[[:space:]]*#include[[:space:]]*<" "^[[:space:]]*int[[:space:]]+main" "\\*[a-zA-Z_][a-zA-Z0-9_]*;" "[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\\(")
     :keywords ("int" "char" "float" "double" "void" "struct" "typedef" "malloc" "printf" "return")
     :score-threshold 2)
    
    (c++-mode
     :patterns ("^[[:space:]]*#include[[:space:]]*<" "class[[:space:]]+[a-zA-Z_]" "namespace[[:space:]]+[a-zA-Z_]" "::[a-zA-Z_]" "std::")
     :keywords ("class" "namespace" "public" "private" "protected" "virtual" "template" "std" "cout" "endl")
     :score-threshold 2)
    
    (rust-mode
     :patterns ("fn[[:space:]]+[a-zA-Z_]" "let[[:space:]]+mut" "use[[:space:]]+[a-zA-Z_:]+;" "impl[[:space:]]+[a-zA-Z_]" "struct[[:space:]]+[a-zA-Z_]")
     :keywords ("fn" "let" "mut" "use" "impl" "struct" "enum" "match" "pub" "crate")
     :score-threshold 2)
    
    (go-mode
     :patterns ("package[[:space:]]+[a-zA-Z_]" "func[[:space:]]+[a-zA-Z_]" "import[[:space:]]+\"" ":=[[:space:]]*")
     :keywords ("package" "func" "import" "var" "const" "type" "interface" "struct" "defer" "go")
     :score-threshold 2)
    
    (java-mode
     :patterns ("public[[:space:]]+class[[:space:]]+[a-zA-Z_]" "import[[:space:]]+[a-zA-Z_.]+;" "public[[:space:]]+static[[:space:]]+void[[:space:]]+main")
     :keywords ("public" "private" "protected" "class" "interface" "import" "package" "static" "final" "void")
     :score-threshold 2)
    
    (kotlin-mode
     :patterns ("fun[[:space:]]+[a-zA-Z_]" "class[[:space:]]+[a-zA-Z_]" "val[[:space:]]+[a-zA-Z_]" "var[[:space:]]+[a-zA-Z_]")
     :keywords ("fun" "val" "var" "class" "object" "interface" "data" "sealed" "when" "is")
     :score-threshold 2)
    
    (swift-mode
     :patterns ("func[[:space:]]+[a-zA-Z_]" "class[[:space:]]+[a-zA-Z_]" "let[[:space:]]+[a-zA-Z_]" "var[[:space:]]+[a-zA-Z_]" "import[[:space:]]+[a-zA-Z_]+")
     :keywords ("func" "let" "var" "class" "struct" "enum" "protocol" "import" "override" "init")
     :score-threshold 2)
    
    (php-mode
     :patterns ("^[[:space:]]*<\\?php" "\\$[a-zA-Z_][a-zA-Z0-9_]*" "function[[:space:]]+[a-zA-Z_]" "class[[:space:]]+[a-zA-Z_]")
     :keywords ("function" "class" "public" "private" "protected" "echo" "print" "array" "foreach" "endif")
     :score-threshold 2)
    
    (ruby-mode
     :patterns ("def[[:space:]]+[a-zA-Z_]" "class[[:space:]]+[a-zA-Z_]" "module[[:space:]]+[a-zA-Z_]" "@[a-zA-Z_]")
     :keywords ("def" "class" "module" "end" "if" "unless" "puts" "require" "attr_accessor" "initialize")
     :score-threshold 2)
    
    (scala-mode
     :patterns ("def[[:space:]]+[a-zA-Z_]" "class[[:space:]]+[a-zA-Z_]" "object[[:space:]]+[a-zA-Z_]" "val[[:space:]]+[a-zA-Z_]" "var[[:space:]]+[a-zA-Z_]")
     :keywords ("def" "val" "var" "class" "object" "trait" "case" "match" "import" "package")
     :score-threshold 2)
    
    (haskell-mode
     :patterns ("[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*::" "module[[:space:]]+[A-Z][a-zA-Z0-9_.]*" "import[[:space:]]+[A-Z][a-zA-Z0-9_.]")
     :keywords ("module" "import" "data" "type" "class" "instance" "where" "let" "in" "case")
     :score-threshold 2)
    
    (erlang-mode
     :patterns ("-module[[:space:]]*(" "-export[[:space:]]*(" "[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*(" "\\.")
     :keywords ("module" "export" "import" "case" "of" "if" "when" "receive" "after" "end")
     :score-threshold 2)
    
    (elixir-mode
     :patterns ("defmodule[[:space:]]+[A-Z][a-zA-Z0-9_.]+" "def[[:space:]]+[a-zA-Z_]" "defp[[:space:]]+[a-zA-Z_]" "@[a-zA-Z_]")
     :keywords ("defmodule" "def" "defp" "do" "end" "if" "unless" "case" "cond" "with")
     :score-threshold 2)
    
    (clojure-mode
     :patterns ("^[[:space:]]*(" "defn[[:space:]]+[a-zA-Z_-]" "def[[:space:]]+[a-zA-Z_-]" "ns[[:space:]]+[a-zA-Z_.-]+")
     :keywords ("defn" "def" "let" "fn" "ns" "require" "import" "if" "when" "cond")
     :score-threshold 2)
    
    (typescript-mode
     :patterns ("interface[[:space:]]+[a-zA-Z_]" "type[[:space:]]+[a-zA-Z_]" ":[[:space:]]*[a-zA-Z_]" "function[[:space:]]+[a-zA-Z_]")
     :keywords ("interface" "type" "function" "const" "let" "var" "class" "extends" "implements" "export")
     :score-threshold 2)
    
    (dart-mode
     :patterns ("class[[:space:]]+[a-zA-Z_]" "void[[:space:]]+main" "import[[:space:]]*'" "library[[:space:]]+[a-zA-Z_]")
     :keywords ("class" "void" "main" "import" "library" "final" "const" "var" "String" "int")
     :score-threshold 2))
  "List of heuristics for mode detection.
Each entry is a list of (MODE :patterns PATTERNS :keywords KEYWORDS :score-threshold THRESHOLD).")

(defun guess-a-mode--calculate-score (mode-spec)
  "Calculate score for MODE-SPEC based on buffer content."
  (let ((patterns (plist-get (cdr mode-spec) :patterns))
        (keywords (plist-get (cdr mode-spec) :keywords))
        (score 0))
    
    ;; Score based on pattern matches
    (dolist (pattern patterns)
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward pattern nil t)
          (setq score (1+ score)))))
    
    ;; Score based on keyword frequency
    (dolist (keyword keywords)
      (save-excursion
        (goto-char (point-min))
        (let ((case-fold-search t))
          (while (search-forward keyword nil t)
            (setq score (+ score 0.5))))))
    
    (when guess-a-mode-verbose
      (message "Mode %s scored: %s" (car mode-spec) score))
    
    score))

(defun guess-a-mode--detect-by-content ()
  "Detect mode based on buffer content using heuristics."
  (let ((candidates '())
        (best-mode nil)
        (best-score 0))
    
    ;; Calculate scores for all modes
    (dolist (mode-spec guess-a-mode-heuristics)
      (let* ((mode (car mode-spec))
             (threshold (plist-get (cdr mode-spec) :score-threshold))
             (score (guess-a-mode--calculate-score mode-spec)))
        
        (when (>= score threshold)
          (push (cons mode score) candidates)
          (when (> score best-score)
            (setq best-score score
                  best-mode mode)))))
    
    (when guess-a-mode-verbose
      (message "Content detection candidates: %s" candidates)
      (when best-mode
        (message "Best content-based match: %s (score: %s)" best-mode best-score)))
    
    best-mode))

(defun guess-a-mode--detect-by-first-line ()
  "Detect mode based on first line patterns."
  (save-excursion
    (goto-char (point-min))
    (let ((first-line (buffer-substring-no-properties 
                      (point) (min (+ (point) 200) (point-max)))))
      (cond
       ((string-match-p "^<\\?xml" first-line) 'xml-mode)
       ((string-match-p "^<!DOCTYPE html" first-line) 'html-mode)
       ((string-match-p "^{\\s-*\"" first-line) 'json-mode)
       ((string-match-p "^---\\s-*$" first-line) 'yaml-mode)
       (t nil)))))

(defun guess-a-mode--safe-mode-p (mode)
  "Check if MODE is safe to activate."
  (and (symbolp mode)
       (fboundp mode)
       (string-match-p "-mode$" (symbol-name mode))))

;;;###autoload
(defun guess-a-mode ()
  "Guess and set the major mode for the current buffer."
  (interactive)
  (let ((original-mode major-mode)
        (detected-mode nil))
    
    (when guess-a-mode-verbose
      (message "Starting mode detection for buffer: %s" (buffer-name)))
    
    ;; Strategy 1: Try Emacs' built-in auto-mode detection
    (unless detected-mode
      (when guess-a-mode-verbose
        (message "Trying built-in set-auto-mode..."))
      (let ((auto-mode-case-fold nil)
            (buffer-file-name (or buffer-file-name 
                                 (buffer-name))))
        (condition-case nil
            (progn
              (set-auto-mode)
              (unless (eq major-mode original-mode)
                (setq detected-mode major-mode)
                (when guess-a-mode-verbose
                  (message "Built-in detection found: %s" detected-mode))))
          (error nil))))
    
    ;; Strategy 2: Check first line patterns  
    (unless detected-mode
      (when guess-a-mode-verbose
        (message "Trying first-line detection..."))
      (setq detected-mode (guess-a-mode--detect-by-first-line))
      (when (and detected-mode guess-a-mode-verbose)
        (message "First-line detection found: %s" detected-mode)))
    
    ;; Strategy 3: Content-based heuristics
    (unless detected-mode
      (when guess-a-mode-verbose
        (message "Trying content-based detection..."))
      (setq detected-mode (guess-a-mode--detect-by-content))
      (when (and detected-mode guess-a-mode-verbose)
        (message "Content-based detection found: %s" detected-mode)))
    
    ;; Apply the detected mode
    (cond
     ((and detected-mode (guess-a-mode--safe-mode-p detected-mode))
      (funcall detected-mode)
      (when guess-a-mode-verbose
        (message "Applied mode: %s" detected-mode)))
     ((not (eq original-mode 'fundamental-mode))
      (when guess-a-mode-verbose
        (message "No better mode found, keeping: %s" original-mode)))
     (t
      (funcall guess-a-mode-fallback-mode)
      (when guess-a-mode-verbose
        (message "Applied fallback mode: %s" guess-a-mode-fallback-mode))))
    
    ;; Return the final mode
    major-mode))

;;;###autoload
(defun guess-a-mode-add-heuristic (mode patterns keywords threshold)
  "Add a new heuristic for MODE detection.
PATTERNS is a list of regex patterns to match.
KEYWORDS is a list of keywords to look for.
THRESHOLD is the minimum score needed to select this mode."
  (let ((spec (list mode 
                   :patterns patterns 
                   :keywords keywords 
                   :score-threshold threshold)))
    (setq guess-a-mode-heuristics 
          (cons spec (assq-delete-all mode guess-a-mode-heuristics)))))

;;;###autoload
(defun guess-a-mode-remove-heuristic (mode)
  "Remove heuristic for MODE."
  (setq guess-a-mode-heuristics 
        (assq-delete-all mode guess-a-mode-heuristics)))

(provide 'guess-a-mode)

;;; guess-a-mode.el ends here
