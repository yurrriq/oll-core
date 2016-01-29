;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;%                                                                             %
;% This file is part of openLilyLib,                                           %
;%                      ===========                                            %
;% the community library project for GNU LilyPond                              %
;% (https://github.com/openlilylib/openlilylib                                 %
;%              -----------                                                    %
;%                                                                             %
;% openLilyLib is free software: you can redistribute it and/or modify         %
;% it under the terms of the GNU General Public License as published by        %
;% the Free Software Foundation, either version 3 of the License, or           %
;% (at your option) any later version.                                         %
;%                                                                             %
;% openLilyLib is distributed in the hope that it will be useful,              %
;% but WITHOUT ANY WARRANTY; without even the implied warranty of              %
;% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               %
;% GNU General Public License for more details.                                %
;%                                                                             %
;% You should have received a copy of the GNU General Public License           %
;% along with openLilyLib. If not, see <http://www.gnu.org/licenses/>.         %
;%                                                                             %
;% openLilyLib is maintained by Urs Liska, ul@openlilylib.org                  %
;% and others.                                                                 %
;%       Copyright Urs Liska, 2015                                             %
;%                                                                             %
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

(define-module (oll-core internal alist-access))
(use-modules
 (lily))

;;
;; Functions for easier and robust access to nested association lists.
;; Typically useful for implementing option trees.
;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Internal Helper functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Check if a given alist is already defined.
;; This is necessary as (ly:parser-lookup alst) will implicitly
;; create an empty list, which will usually result in strange
;; error conditions when a list name is misspelled.
(define (check-alst funcname alst key-name val)
  (if (not (defined? alst))
      ; TODO: Change this to oll-warning (when this is transfered to oll-core)
      (ly:input-warning (*location*) "
Trying to access non-present alist '~a' with function '~a',
using key '~a' and ~a.  This will create a new alist instead,
which is probably not intended."
      alst funcname key-name
      (if val
          (format "value '~a'" val)
          "no value"))))

;; Set key <key-name> in alist <alst> to value <val>
;; If <in-place> is #t the key is replaced in-place if already present.
;; Otherwise (<in-place> is #f and/or key is not set) is is appended.
(define (set-in-alist alst key-name val in-place)
  (let ((is-present (assq-ref alst key-name)))
    (if (and in-place is-present)
        ;; Set value in-place

        ;
        ; QUESTION:
        ; Is this really necessary, aren't there any Guile functions?
        ;
        (map (lambda (node)
               (if (and (pair? node) (equal? (car node) key-name))
                   (cons key-name val)
                   node))
          alst)
        ;; Append entry, remove from within if necessary
        (append
         (if is-present
             (assoc-remove! alst key-name)
             alst)
         (list (cons key-name val))))))

;; Wrapper function around set-in-alist
;; Is used by \setAlist and \addToAlist
(define (set-a-list funcname alst key-name val in-place)
  (check-alst funcname alst key-name val)
  (ly:parser-define! alst
    (set-in-alist (ly:parser-lookup alst) key-name val in-place)))

;; Set <path> in alist <tree> to value <val>.
;; <path> is a symbol list, with the last element being the actual key.
;; If any node or the final key is not present it is created implicitly.
;; If <in-place> is #t the key is modified in place if already present,
;; otherwise it will be appended.
;; Intermediate nodes are always updated in place if the already exist.
(define (set-in-atree tree path val in-place)
  (let ((key-name (car path)))
    (if (not (list? tree))
        (begin
         (ly:input-warning (*location*) "Not a list. Deleting '~A'" tree)
         (set! tree '())))
    (cond ((> (length path) 1)
            (let ((subtree (assoc-get key-name tree '())))
              (set-in-alist
               tree
               key-name
               ;; Intermediate nodes are always updated in-place
               (set-in-atree subtree (cdr path) val #t)
               in-place)))
      (else
        (set-in-alist tree key-name val in-place)))))

;; Wrapper function around set-in-atree,
;; to be used by \setAtree and \addAtree
(define (set-a-tree atree path val in-place)
   (ly:parser-define! atree
     (set-in-atree (ly:parser-lookup atree) path val in-place)))

;; Recursively walk the nested alist <tree> over the symbol-list <path>
;; and return the value for the last leaf in <path> or #f if the chain
;; is broken at any point.
(define (get-from-subtree tree path)
  (let ((key-name (car path)))
    (cond
     ((> (length path) 1)
      (let ((subtree (assoc-get key-name tree #f)))
        (if (list? subtree)
            (get-from-subtree subtree (cdr path))
            #f)))
     ((= (length path) 1)
      (assoc-get (car path) tree #f))
     (else #f))))

;; Takes the alist <tree> and removes the node <path>,
;; returns a new list.
(define (remove-value tree path)
  (let* ((key-name (car path))
         (subpath (cdr path))
         (subtree (assoc-get key-name tree '())))
    (cond
     ((> (length subpath) 1)
      (set-in-alist tree key-name (remove-value subtree (cdr path)) #t))
     (else
      (set-in-alist tree key-name (assoc-remove! subtree (car subpath)) #t)))))




;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Public interface
;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Processing regular alists

;; Create a new empty list with the name <name>.
;; After this call we can rely on the existence
;; and emptyness of this.
(define-public newAlist
   (define-void-function (name)(symbol?)
     "Creates or resets <name> as an empty list."
         (ly:parser-define! name (list))))

;; Set the node <key-name> to the value <val>.
;; If <key-name> is present it is replaced in-place,
;; otherwise it is appended at the end of the alist.
(define-public setAlist
  (define-void-function (alst key-name val)(symbol? symbol? scheme?)
    (set-a-list 'setAlist alst key-name val #t)))

;; Set the node <key-name> to the value <val>.
;; If <key-name> is present it is moved to the end
;; otherwise it is appended to the alist.
(define-public addToAlist
  (define-void-function (alst key-name val) (symbol? symbol? scheme?)
    (set-a-list 'addToAlist alst key-name val #f)))

;% removes one entry from association list
(define-public removeFromAlist
  (define-void-function (alst key-name)(symbol? symbol?)
    (check-alst 'removeFromAlist alst key-name #f)
    (ly:parser-define! alst
      (assoc-remove! (ly:parser-lookup alst) key-name))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Processing nested alists,
;; called a-trees herein

;; Create a new empty a-tree with the name <name>.
;; This is merely a renamed copy of newAlist as
;; an empty a-tree is actually an empty list.
(define-public newAtree newAlist)

;; Set node <path> in a-tree <atree> to value <val>.
;; If <path> is present modify in-place, otherwise append the node.
;; Intermediate nodes are created if necessary.
(define-public setAtree
  (define-void-function (atree path val)(symbol? list? scheme?)
    (set-a-tree atree path val #t)))

;; Set node <path> in a-tree <atree> to value <val>.
;; If <path> is present it is moved to the end, otherwise appended
;; Intermediate nodes are created if necessary.
(define-public addAtree
  (define-void-function (atree path val)(symbol? list? scheme?)
    (set-a-tree atree path val #f)))

;; Retrieve a value from path <path> in an a-tree <atree>.
;; If the key (last element) or any element in <path> is not present
;; #f is returned.
;; NOTE: There's an ambiguity between a non-present key and a key
;; with the explicit value #f
(define-public getAtree
  (define-scheme-function (atree path)(symbol? symbol-list-or-symbol?)
   (let ((tree (ly:parser-lookup atree)))
     (check-alst 'getAtree atree path #f)
     (if (list? tree)
         (get-from-subtree tree path)
         (begin
          (ly:input-warning (*location*) "~A is not list (~A)" atree tree)
          #f)))))

;; Remove node <path> from a-tree <atree>.
;; If <path> isn't present in <atree> it is not modified.
(define-public remAtree
  (define-void-function (atree path)(symbol? list?)
    (check-alst 'remAtree atree path #f)
    (ly:parser-define! atree
      (remove-value (ly:parser-lookup atree) path))))
