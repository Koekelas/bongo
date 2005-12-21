;;; bongo.el --- buffer-oriented media player for Emacs
;; Copyright (C) 2005  Daniel Brockman
;; Copyright (C) 2005  Lars Öhrman

;; Author: Daniel Brockman <daniel@brockman.se>
;; URL: http://www.brockman.se/software/bongo/
;; Created: September 3, 2005

;; This file is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of
;; the License, or (at your option) any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty
;; of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
;; See the GNU General Public License for more details.

;; You should have received a copy of the GNU General Public
;; License along with GNU Emacs; if not, write to the Free
;; Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Code:

(defgroup bongo nil
  "Buffer-oriented media player."
  :prefix "bongo-"
  :group 'multimedia
  :group 'applications)

(defcustom bongo-fields '(artist album track)
  "The fields that will be used to describe tracks and headers.

This list names the possible keys of a type of alist called an infoset.
The value of a field may be some arbitrarily complex data structure,
but the name of each field must be a simple symbol.

By default, each field consists of another alist:
 * the `artist' field consists of a single mandatory `name' subfield;
 * the `album' field consists of both a mandatory `title' subfield
   and an optional `year' subfield; and finally,
 * the `track' field consists of a mandatory `title' subfield
   and an optional `index' subfield.

Currently, this list needs to be completely ordered, starting with
the most general field and ending with the most specific field.
This restriction may be relaxed in the future to either allow partially
ordered field lists, or to abandon the hard-coded ordering completely.

The meaning and content of the fields are defined implicitly by the
functions that use and operate on fields and infosets (sets of fields).
Therefore, if you change this list, you probably also need to change
 (a) either `bongo-infoset-formatting-function' or
     `bongo-field-formatting-function', and
 (b) `bongo-infoset-from-file-name-function'."
  :type '(repeat symbol)
  :group 'bongo)

(defcustom bongo-default-buffer-name "*Playlist*"
  "The name of the default Bongo buffer."
  :type 'string
  :group 'bongo)



(defgroup bongo-faces nil
  "Faces used by Bongo."
  :group 'bongo)

(defface bongo-comment
  '((t (:inherit font-lock-comment-face)))
  "Face used for comments in Bongo buffers."
  :group 'bongo-faces)

(defface bongo-artist
  '((t (:inherit font-lock-keyword-face)))
  "Face used for Bongo artist names."
  :group 'bongo-faces)

(defface bongo-album
  '((t (:inherit default)))
  "Face used for Bongo albums (year, title, and punctuation)."
  :group 'bongo-faces)

(defface bongo-album-title
  '((t (:inherit (font-lock-type-face bongo-album))))
  "Face used for Bongo album titles."
  :group 'bongo-faces)

(defface bongo-album-year
  '((t (:inherit bongo-album)))
  "Face used for Bongo album years."
  :group 'bongo-faces)

(defface bongo-track
  '((t (:inherit default)))
  "Face used for Bongo tracks (index, title, and punctuation)."
  :group 'bongo-faces)

(defface bongo-track-title
  '((t (:inherit (font-lock-function-name-face bongo-track))))
  "Face used for Bongo track titles."
  :group 'bongo-faces)

(defface bongo-track-index
  '((t (:inherit bongo-track)))
  "Face used for Bongo track indices."
  :group 'bongo-faces)



(defcustom bongo-gnu-find-program "find"
  "The name of the GNU find executable."
  :type 'string
  :group 'bongo)

(defcustom bongo-gnu-find-extra-arguments
  (when (and (executable-find bongo-gnu-find-program)
             (equal 0 (call-process bongo-gnu-find-program nil nil nil
                                    "-regextype" "emacs" "-prune")))
    '("-regextype" "emacs"))
  "Extra arguments to pass to GNU find."
  :type '(repeat string)
  :group 'bongo)

(defcustom bongo-header-format "[%s]"
  "Template for displaying header lines.
%s means the header line content."
  :type 'string
  :group 'bongo)

(defcustom bongo-indentation-string "  "
  "String prefixed to lines once for each level of indentation."
  :type 'string
  :group 'bongo)

(defcustom bongo-infoset-formatting-function 'bongo-default-format-infoset
  "Function used to convert an info set into a string."
  :type 'function
  :group 'bongo)

(defcustom bongo-field-formatting-function 'bongo-default-format-field
  "Function used to convert an info field into a string.
This is used by the function `bongo-default-format-infoset'."
  :type 'function
  :group 'bongo)

(defcustom bongo-field-separator " —— "
  "String used to separate field values.
This is used by the function `bongo-default-format-field'."
  :type '(choice (const :tag " —— (Unicode dashes)" " —— ")
                 (const :tag " -- (ASCII dashes)" " -- ")
                 string)
  :group 'bongo)

(defcustom bongo-album-format "%t (%y)"
  "Template for displaying albums in Bongo.
This is used by the function `bongo-default-format-field'.
%t means the album title.
%y means the album year."
  :type 'string
  :group 'bongo)

(defcustom bongo-track-format "%i. %t"
  "Template for displaying tracks in Bongo.
This is used by the function `bongo-default-format-field'.
%t means the track title.
%i means the track index."
  :type 'string
  :group 'bongo)

(defcustom bongo-infoset-from-file-name-function
  'bongo-default-infoset-from-file-name
  "Function used to convert file names into infosets."
  :type 'function
  :group 'bongo)

(defcustom bongo-file-name-field-separator " - "
  "String used to split file names into fields.
This is used by `bongo-default-infoset-from-file-name'."
  :type 'string
  :group 'bongo)

(defcustom bongo-file-name-album-year-regexp
  "^\\([0-9]\\{4\\}\\|'?[0-9]\\{2\\}\\)$"
  "Regexp matching album years.
This is used by `bongo-default-infoset-from-file-name'."
  :type 'regexp
  :group 'bongo)

(defcustom bongo-file-name-track-index-regexp "^[0-9]+$"
  "Regexp matching track indices.
This is used by `bongo-default-infoset-from-file-name'."
  :type 'regexp
  :group 'bongo)

(defun bongo-format-header (content)
  "Decorate CONTENT so as to make it look like a header.
This function uses `bongo-header-format'."
  (format bongo-header-format content))

(defun bongo-format-infoset (infoset)
  "Represent INFOSET as a user-friendly string.
This function just calls `bongo-infoset-formatting-function'."
  (funcall bongo-infoset-formatting-function infoset))

(defun bongo-default-format-infoset (infoset)
  "Format INFOSET by calling `bongo-format-field' on each field.
Separate the obtained formatted field values by `bongo-field-separator'."
  (mapconcat 'bongo-format-field infoset bongo-field-separator))

(defun bongo-join-fields (values)
  (mapconcat 'identity values bongo-field-separator))

(defun bongo-format-field (field)
  (funcall bongo-field-formatting-function field))

(defun bongo-default-format-field (field)
  (let ((type (car field))
        (data (cdr field)))
    (cond
     ((eq type 'artist)
      (propertize (bongo-alist-get data 'name) 'face 'bongo-artist))
     ((eq type 'album)
      (let ((title (bongo-alist-get data 'title))
            (year (bongo-alist-get data 'year)))
        (if (null year) (propertize title 'face 'bongo-album-title)
          (format-spec bongo-album-format
                       `((?t . ,(propertize
                                 title 'face 'bongo-album-title))
                         (?y . ,(propertize
                                 year 'face 'bongo-album-year)))))))
     ((eq type 'track)
      (let ((title (bongo-alist-get data 'title))
            (index (bongo-alist-get data 'index)))
        (if (null index) (propertize title 'face 'bongo-track-title)
          (format-spec bongo-track-format
                       `((?t . ,(propertize
                                 title 'face 'bongo-track-title))
                         (?i . ,(propertize
                                 index 'face 'bongo-track-index))))))))))

(defun bongo-infoset-from-file-name (file-name)
  (funcall bongo-infoset-from-file-name-function file-name))

(defun bongo-default-infoset-from-file-name (file-name)
  (let* ((base-name (file-name-sans-extension
                     (file-name-nondirectory file-name)))
         (values (split-string base-name bongo-file-name-field-separator)))
    (when (> (length values) 5)
      (let ((fifth-and-rest (nthcdr 4 values)))
        (setcar fifth-and-rest (bongo-join-fields fifth-and-rest))
        (setcdr fifth-and-rest nil)))
    (cond
     ((= 5 (length values))
      (if (string-match bongo-file-name-track-index-regexp (nth 3 values))
          `((artist (name . ,(nth 0 values)))
            (album (year . ,(nth 1 values))
                   (title . ,(nth 2 values)))
            (track (index . ,(nth 3 values))
                   (title . ,(nth 4 values))))
        `((artist (name . ,(nth 0 values)))
          (album (year . ,(nth 1 values))
                 (title . ,(nth 2 values)))
          (track (title . ,(bongo-join-fields (nthcdr 3 values)))))))
     ((and (= 4 (length values))
           (string-match bongo-file-name-track-index-regexp (nth 2 values)))
      `((artist (name . ,(nth 0 values)))
        (album (title . ,(nth 1 values)))
        (track (index . ,(nth 2 values))
               (title . ,(nth 3 values)))))
     ((and (= 4 (length values))
           (string-match bongo-file-name-album-year-regexp (nth 1 values)))
      `((artist (name . ,(nth 0 values)))
        (album (year  . ,(nth 1 values))
               (title . ,(nth 2 values)))
        (track (title . ,(nth 3 values)))))
     ((= 4 (length values))
      `((artist (name . ,(nth 0 values)))
        (album (title . ,(nth 1 values)))
        (track (title . ,(bongo-join-fields (nthcdr 2 values))))))
     ((= 3 (length values))
      `((artist (name . ,(nth 0 values)))
        (album (title . ,(nth 1 values)))
        (track (title . ,(nth 2 values)))))
     ((= 2 (length values))
      `((artist (name . ,(nth 0 values)))
        (track (title . ,(nth 1 values)))))
     ((= 1 (length values))
      `((track (title . ,(nth 0 values))))))))

(defun bongo-simple-infoset-from-file-name (file-name)
  `((track (title . ,(file-name-sans-extension
                      (file-name-nondirectory file-name))))))


;;;; Basic point-manipulation routines

(defun bongo-goto-point (point)
  "Set point to POINT, if POINT is non-nil.
POINT may be a number, a marker or nil."
  (when point (goto-char point)))

(defun bongo-skip-invisible ()
  "Move point to the next visible character.
If point is already on a visible character, do nothing."
  (while (and (not (eobp)) (line-move-invisible-p (point)))
    (goto-char (next-char-property-change (point)))))

(defun bongo-point-at-bol (&optional point)
  "Return the first character position of the line at POINT."
  (save-excursion (bongo-goto-point point) (point-at-bol)))

(defun bongo-point-at-eol (&optional point)
  "Return the last character position of the line at POINT."
  (save-excursion (bongo-goto-point point) (point-at-eol)))

(defun bongo-first-line-p (&optional point)
  "Return non-nil if POINT is on the first line."
  (= (bongo-point-at-bol point) (point-min)))

(defun bongo-last-line-p (&optional point)
  "Return non-nil if POINT is on the last line.
An empty line at the end of the buffer doesn't count."
  (>= (1+ (bongo-point-at-eol point)) (point-max)))

(defun bongo-first-object-line-p (&optional point)
  "Return non-nil if POINT is on the first object line."
  (null (bongo-point-at-previous-object-line point)))

(defun bongo-last-object-line-p (&optional point)
  "Return non-nil if POINT is on the last object line."
  (null (bongo-point-at-next-object-line point)))

(defalias 'bongo-point-before-line #'bongo-point-at-bol
  "Return the first character position of the line at POINT.")

(defun bongo-point-after-line (&optional point)
  "Return the first character position after the line at POINT.
For lines that end with newlines, the point after the line
is the same as the point before the next line."
  (let ((eol (bongo-point-at-eol point)))
    (if (= eol (point-max)) eol (1+ eol))))

(defun bongo-point-before-previous-line (&optional point)
  "Return the first point of the line before the one at POINT.
If the line at POINT is the first line, return nil."
  (unless (bongo-first-line-p point)
    (bongo-point-at-bol (1- (bongo-point-at-bol point)))))

(defun bongo-point-before-next-line (&optional point)
  "Return the first point of the line after the one at POINT.
If the line at POINT is the last line, return nil."
  (unless (bongo-last-line-p point)
    (1+ (bongo-point-at-eol point))))

(defalias 'bongo-point-at-previous-line
  #'bongo-point-before-previous-line)

(defalias 'bongo-point-at-next-line
  #'bongo-point-before-next-line)

(defun bongo-point-before-previous-line-satisfying (predicate &optional point)
  "Return the position of the previous line satisfying PREDICATE.
If POINT is non-nil, the search starts before the line at POINT.
If POINT is nil, it starts before the current line.
If no matching line is found, return nil."
  (save-excursion
    (bongo-goto-point point)
    (when (not (bongo-first-line-p))
      (let (match)
        (while (and (not (bobp)) (not match))
          (forward-line -1)
          (when (funcall predicate)
            (setq match t)))
        (when match (point))))))

(defalias 'bongo-point-at-previous-line-satisfying
  #'bongo-point-before-previous-line-satisfying)

(defun bongo-point-before-next-line-satisfying (predicate &optional point)
  "Return the position of the next line satisfying PREDICATE.
If POINT is non-nil, the search starts after the line at POINT.
If POINT is nil, it starts after the current line.
If no matching line is found, return nil."
  (save-excursion
    (bongo-goto-point point)
    (when (not (bongo-last-line-p))
      (let (match)
        (while (and (not (eobp)) (not match))
          (forward-line)
          (when (funcall predicate)
            (setq match t)))
        (when match (point))))))

(defalias 'bongo-point-at-next-line-satisfying
  #'bongo-point-before-next-line-satisfying)

(defun bongo-point-after-next-line-satisfying (predicate &optional point)
  "Return the position after the next line satisfying PREDICATE.
This function works like `bongo-point-before-next-line-satisfying'."
  (let ((before-next (bongo-point-before-next-line-satisfying
                      predicate point)))
    (when before-next
      (bongo-point-at-eol before-next))))

(defun bongo-point-before-previous-object-line (&optional point)
  "Return the character position of the previous object line.
If POINT is non-nil, start before that line; otherwise,
  start before the current line.
If no object line is found before the starting line, return nil."
  (bongo-point-before-previous-line-satisfying 'bongo-object-line-p point))

(defalias 'bongo-point-at-previous-object-line
  #'bongo-point-before-previous-object-line)

(defun bongo-point-before-next-object-line (&optional point)
  "Return the character position of the next object line.
If POINT is non-nil, start after that line; otherwise,
  start after the current line.
If no object line is found after the starting line, return nil."
  (bongo-point-before-next-line-satisfying 'bongo-object-line-p point))

(defalias 'bongo-point-at-next-object-line
  #'bongo-point-before-next-object-line)

(defun bongo-point-after-next-object-line (&optional point)
  "Return the character position after the next object line.
This function works like `bongo-point-before-next-object-line'."
  (bongo-point-after-next-line-satisfying 'bongo-object-line-p point))

(defun bongo-backward-object-line ()
  "If possible, move point to the previous object line.
If there is no previous object line, move to the beginning of the buffer.
Return non-nil if point was moved to an object line."
  (let ((position (bongo-point-at-previous-object-line)))
    (prog1 (not (null position))
      (goto-char (or position (point-min))))))

(defun bongo-forward-object-line ()
  "If possible, move point to the next object line.
If there is no next object line, move to the end of the buffer.
Return non-nil if point was moved to an object line."
  (let ((position (bongo-point-at-next-object-line)))
    (prog1 (not (null position))
      (goto-char (or position (point-max))))))

(defun bongo-point-before-next-track-line (&optional point)
  "Return the character position of the next track line.
If POINT is non-nil, start after that line; otherwise,
  start after the current line.
If no track line is found after the starting line, return nil."
  (bongo-point-before-next-line-satisfying 'bongo-track-line-p point))

(defalias 'bongo-point-at-next-track-line
  #'bongo-point-before-next-track-line)

(defun bongo-point-before-previous-track-line (&optional point)
  "Return the character position of the previous track line.
If POINT is non-nil, start before that line; otherwise,
  start before the current line.
If no track line is found before the starting line, return nil."
  (bongo-point-before-previous-line-satisfying 'bongo-track-line-p point))

(defalias 'bongo-point-at-previous-track-line
  #'bongo-point-before-previous-track-line)

(defun bongo-point-after-section (&optional point)
  "Return the point after the section with its header on POINT."
  (unless (bongo-header-line-p point)
    (error "Point is not on a section header"))
  (save-excursion 
    (bongo-goto-point point)
    (let ((indentation (bongo-line-indentation)))
      (bongo-forward-object-line)
      (while (and (> (bongo-line-indentation) indentation)
                  (not (eobp)))
        (bongo-forward-object-line))
      (point))))

(defun bongo-track-infoset (&optional point)
  "Return the infoset for the track at POINT.
You should use `bongo-line-infoset' most of the time."
  (unless (bongo-track-line-p point)
    (error "Point is not on a track line"))
  (bongo-infoset-from-file-name (bongo-line-file-name point)))

(defun bongo-header-infoset (&optional point)
  "Return the infoset for the header at POINT.
You should use `bongo-line-infoset' most of the time."
  (unless (bongo-header-line-p point)
    (error "Point is not on a header line"))
  (let ((next-track (bongo-point-at-next-track-line)))
    (if (null next-track)
        (error "Dangling header line")
      (bongo-filter-alist (bongo-line-fields)
                          (bongo-track-infoset next-track)))))

(defun bongo-line-infoset (&optional point)
  "Return the infoset for the line at POINT.
For track lines, the infoset is obtained by passing the file name to
  `bongo-file-name-parsing-function'.
For header lines, it is derived from the `bongo-fields' text property
  and the infoset of the nearest following track line."
    (cond
     ((bongo-track-line-p point) (bongo-track-infoset point))
     ((bongo-header-line-p point) (bongo-header-infoset point))))

(defun bongo-line-internal-infoset (&optional point)
  "Return the internal infoset for the line at POINT.
The internal infoset contains values of the internal fields only."
  (bongo-filter-alist (bongo-line-internal-fields point)
                      (bongo-line-infoset point)))

(defun bongo-line-field-value (field &optional point)
  "Return the value of FIELD for the line at POINT."
  (assoc field (bongo-line-infoset point)))

(defun bongo-line-field-values (fields &optional point)
  "Return the values of FIELDS for the line at POINT."
  (bongo-filter-alist fields (bongo-line-infoset point)))

(defun bongo-line-fields (&optional point)
  "Return the names of the fields defined for the line at POINT."
  (if (bongo-header-line-p point)
      (bongo-line-get-property 'bongo-fields point)
    (mapcar 'car (bongo-line-infoset point))))

(defun bongo-line-external-fields (&optional point)
  "Return the names of the fields external to the line at POINT."
  (bongo-line-get-property 'bongo-external-fields point))

(defun bongo-line-set-external-fields (fields &optional point)
  "Set FIELDS to be external to the line at POINT.
FIELDS should be a list of field names."
  (save-excursion
    (bongo-goto-point point)
    (bongo-line-set-property 'bongo-external-fields fields)
    (if (bongo-empty-header-line-p)
        (bongo-delete-line)
      (bongo-redisplay-line))))

(defun bongo-line-internal-fields (&optional point)
  "Return the names of the fields internal to the line at POINT."
  (set-difference (bongo-line-fields point)
                  (bongo-line-external-fields point)))

(defun bongo-line-indentation (&optional point)
  "Return the number of external fields of the line at POINT."
  (length (bongo-line-external-fields point)))

(defun bongo-line-indented-p (&optional point)
  (> (bongo-line-indentation point) 0))

(defun bongo-line-external-fields-proposal (&optional point)
  "Return the external fields proposal of the line at POINT.
This proposal is a list of field names that subsequent lines can
externalize if their field values match those of this line.

For track lines, this is always the same as the external field names.
For header lines, the internal field names are also added."
  (cond ((bongo-track-line-p point)
         (bongo-line-external-fields point))
        ((bongo-header-line-p point)
         (append (bongo-line-external-fields point)
                 (bongo-line-internal-fields point)))))

(defun bongo-line-indentation-proposal (&optional point)
  "Return the number of external fields proposed by the line at POINT.
See `bongo-line-external-fields-proposal'."
  (cond ((bongo-track-line-p point)
         (bongo-line-indentation point))
        ((bongo-header-line-p point)
         (+ (length (bongo-line-external-fields point))
            (length (bongo-line-internal-fields point))))))

(defun bongo-line-proposed-external-fields (&optional point)
  "Return the external fields proposed to the line at POINT.
This is nil for the first line, and equal to the external field names
proposal of the previous object line for all other lines."
  (if (bongo-first-object-line-p point) nil
    (bongo-line-external-fields-proposal
     (bongo-point-at-previous-object-line point))))

(defun bongo-line-proposed-indentation (&optional point)
  "Return the number of external fields proposed to the line at POINT.
See `bongo-line-proposed-external-fields'."
  (if (bongo-first-object-line-p point) 0
    (bongo-line-indentation-proposal
     (bongo-point-at-previous-object-line point))))

;;; (defun bongo-line-relatively-outdented-p ()
;;;   (< (bongo-line-indentation) (bongo-line-proposed-indentation)))

(defun bongo-line-file-name (&optional point)
  "Return the `bongo-file-name' text property of the file at POINT.
This will be nil for header lines and non-nil for track lines."
  (bongo-line-get-property 'bongo-file-name point))

(defun bongo-track-line-p (&optional point)
  "Return non-nil if the line at POINT is a track line."
  (not (null (bongo-line-file-name point))))

(defun bongo-header-line-p (&optional point)
  "Return non-nil if the line at POINT is a header line."
  (bongo-line-get-property 'bongo-header-p point))

(defun bongo-object-line-p (&optional point)
  "Return non-nil if the line at POINT is an object line.
Object lines are either track lines or header lines."
  (or (bongo-track-line-p point) (bongo-header-line-p point)))

(defun bongo-empty-header-line-p (&optional point)
  "Return non-nil if the line at POINT is an empty header line.
Empty header lines have no internal fields and are not supposed ever
to exist for long enough to be visible to the user."
  (and (bongo-header-line-p point)
       (null (bongo-line-internal-fields point))))


;;;; General convenience routines

;;; (defmacro nor (&rest conditions)
;;;   `(not (or ,@conditions)))

(defun bongo-shortest (a b)
  "Return the shorter of the lists A and B."
  (if (<= (length a) (length b)) a b))

(defun bongo-longest (a b)
  "Return the longer of the lists A and B."
  (if (>= (length a) (length b)) a b))

(defun bongo-equally-long-p (a b)
  "Return non-nil if the lists A and B have equal length."
  (= (length a) (length b)))

(defun bongo-set-equal-p (a b)
  "Return non-nil if A and B have equal elements.
The order of the elements is not significant."
  (null (set-exclusive-or a b)))

(defun bongo-alist-get (alist key)
  "Return the cdr of the element in ALIST whose car equals KEY.
If no such element exists, return nil."
  (cdr-safe (assoc key alist)))

(defun bongo-alist-put (alist key value)
  "Set the cdr of the element in ALIST whose car equals KEY to VALUE.
If no such element exists, add a new element to the start of ALIST.
This function destructively modifies ALIST and returns the new head.
If ALIST is a symbol, operate on the vaule of that symbol instead."
  (if (and (symbolp alist) (not (null alist)))
      (set alist (bongo-alist-put (symbol-value alist) key value))
    (let ((entry (assoc key alist)))
      (if entry (prog1 alist (setcdr entry value))
        (cons (cons key value) alist)))))

(defun bongo-filter-alist (keys alist)
  "Return a new list of each pair in ALIST whose car is in KEYS.
Key comparisons are done with `eq'."
  (remove-if-not (lambda (pair)
                   (memq (car pair) keys)) alist))

(defun bongo-filter-plist (keys plist)
  "Return a new list of each property in PLIST whose name is in KEYS.
Key comparisons are done with `eq'."
  (let (new-plist)
    (while plist
      (when (memq (car plist) keys)
        (setq new-plist `(,(car plist) ,(cadr plist) ,@new-plist)))
      (setq plist (cddr plist)))
    new-plist))

(if (and (fboundp 'process-put) (fboundp 'process-get))
    (progn
      (defalias 'bongo-process-get #'process-get)
      (defalias 'bongo-process-put #'process-put))

  (defvar bongo-process-alist nil)

  (defun bongo-process-plist (process)
    (bongo-alist-get bongo-process-alist process))

  (defun bongo-process-set-plist (process plist)
    (bongo-alist-put 'bongo-process-alist process plist))

  (defun bongo-process-get (process property)
    "Return the value of PROPERTY for PROCESS."
    (plist-get (bongo-process-plist process) property))

  (defun bongo-process-put (process property value)
    "Change the value of PROPERTY for PROCESS to VALUE."
    (bongo-set-process-plist
     process (plist-put (bongo-process-plist process)
                        property value))))


;;;; Line-oriented convenience routines

(defun bongo-ensure-final-newline ()
  "Make sure the last line in the current buffer ends with a newline.
Do nothing if the current buffer is empty."
  (or (= (point-min) (point-max))
      (= (char-before (point-max)) ?\n)
      (save-excursion
        (goto-char (point-max))
        (insert "\n"))))

(defun bongo-delete-line (&optional point)
  "Delete the line at POINT."
  (let ((inhibit-read-only t))
    (delete-region (bongo-point-before-line point)
                   (bongo-point-after-line point))))

(defun bongo-extract-line (&optional point)
  "Delete the line at POINT and return its content.
The content includes the final newline, if any."
  (prog1 (buffer-substring (bongo-point-before-line point)
                           (bongo-point-after-line point))
    (bongo-delete-line point)))

(defun bongo-clear-line (&optional point)
  "Remove all contents of the line at POINT."
  (let ((inhibit-read-only t))
    (bongo-ensure-final-newline)
    (save-excursion
      (bongo-goto-point point)
      ;; Avoid deleting the newline, because that would
      ;; cause the markers on this line to become mixed up
      ;; with those on the next line.
      (delete-region (point-at-bol) (point-at-eol))
      ;; Remove all text properties from the newline.
      (set-text-properties (point) (1+ (point)) nil))))

(defun bongo-region-line-count (beg end)
  "Return the number of lines between BEG and END.
If BEG and END are the same, return 0.
If they are distinct but on the same line, return 1."
  (save-excursion
    (goto-char beg)
    (let ((size 0))
      (while (< (point) end)
        (setq size (1+ size))
        (forward-line))
      size)))


;;;; Text properties

;;; XXX: Should rename these to `bongo-get-line-property', etc.

(defun bongo-line-get-property (name &optional point)
  "Return the value of the text property NAME on the line at POINT.
Actually only look at the terminating newline."
  (get-text-property (bongo-point-at-eol point) name))

(defvar bongo-line-semantic-properties
  (list 'bongo-file-name 'bongo-header-p
        'bongo-fields 'bongo-external-fields
        'bongo-player)
  "The list of semantic text properties used in Bongo buffers.
When redisplaying lines, semantic text properties are preserved,
whereas all other text properties (e.g., `face') are discarded.")

(defun bongo-line-get-semantic-properties (&optional point)
  "Return the list of semantic text properties on the line at POINT.
Actually only look at the terminating newline.

The value of `bongo-line-semantic-properties' determines which
text properties are considered \"semantic\" by this function."
  (bongo-filter-plist bongo-line-semantic-properties
                      (text-properties-at (bongo-point-at-eol point))))

(defun bongo-line-set-property (name value &optional point)
  "Set the text property NAME to VALUE on the line at POINT.
The text property will only be set for the terminating newline."
  (let ((inhibit-read-only t)
        (position (bongo-point-at-eol point)))
    (bongo-ensure-final-newline)
    (put-text-property position (1+ position) name value)))

(defun bongo-line-set-properties (properties &optional point)
  "Set the text properties PROPERTIES on the line at POINT.
The text properties will only be set for the terminating newline."
  (let ((inhibit-read-only t)
        (position (bongo-point-at-eol point)))
    (bongo-ensure-final-newline)
    (add-text-properties position (1+ position) properties)))

(defun bongo-line-remove-property (name &optional point)
  "Remove the text property NAME from the line at POINT.
The text properties will only be removed from the terminating newline."
  (let ((inhibit-read-only t)
        (position (bongo-point-at-eol point)))
    (bongo-ensure-final-newline)
    (remove-text-properties position (1+ position) (list name nil))))

(defun bongo-keep-text-properties (beg end keys)
  "Keep only some properties in text from BEG to END."
  (save-excursion
    (save-restriction
      (narrow-to-region beg end)
      (goto-char (point-min))
      (while (not (eobp))
        (let* ((properties (text-properties-at (point)))
               (kept-properties (bongo-filter-plist keys properties))
               (next (or (next-property-change (point)) (point-max))))
          (set-text-properties (point) next kept-properties)
          (goto-char next))))))


;;;; Sectioning

(defun bongo-region-field-common-p (beg end field)
  "Return non-nil if FIELD is common between BEG and END.
FIELD should be the name of a field (i.e., a symbol).
A field is common in a region if all object lines inside
the region share the same value for the field."
  (save-excursion
    (let ((last-value nil)
          (common-p t))
      (goto-char beg)
      (when (not (bongo-object-line-p))
        (bongo-forward-object-line))
      (when (< (point) end)
        (setq last-value (bongo-line-field-value field))
        (bongo-forward-object-line)
        (while (and common-p (< (point) end))
          (if (equal last-value (bongo-line-field-value field))
              (bongo-forward-object-line)
            (setq common-p nil))))
      common-p)))

;; XXX: This will not work properly unless the fields are
;;      strictly hierarchical.
(defun bongo-region-common-fields (beg end)
  "Return the names of all fields that are common between BEG and END.
See `bongo-region-common-field-name-p'."
  (let ((fields (reverse bongo-fields))
        (common-fields nil))
    (while fields
      (if (bongo-region-field-common-p beg end (car fields))
          (when (null common-fields)
            (setq common-fields fields))
        (setq common-fields nil))
      (setq fields (cdr fields)))
    common-fields))

(defun bongo-common-fields-at-point (&optional point)
  "Return the names of all fields that are common at POINT.
A field is common at POINT if it is common in the region around
the object at POINT and either the previous or the next object."
  (save-excursion
    (bongo-goto-point point)
    (unless (bongo-object-line-p)
      (error "Point is not on an object line"))
    (let ((before-previous (bongo-point-before-previous-object-line))
          (after-next (bongo-point-after-next-object-line)))
      (bongo-longest
       (when before-previous
         (bongo-region-common-fields before-previous
                                     (bongo-point-after-line)))
       (when after-next
         (bongo-region-common-fields (bongo-point-before-line)
                                     after-next))))))

;; XXX: This will not work properly unless the fields are
;;      strictly hierarchical.
(defun bongo-region-fields-external-p (beg end fields)
  "Return non-nil if FIELDS are external between BEG and END.
Return nil if there is a field in FIELDS that is not external for
at least one line in the region."
  (save-excursion
    (let ((external-p t))
      (goto-char beg)
      (while (and (< (point) end) external-p)
        (when (< (bongo-line-indentation) (length fields))
          (setq external-p nil))
        (forward-line))
      external-p)))

;;; (defun bongo-external-fields-in-region-equal-p (beg end)
;;;   "In Bongo, return the fields that are external in the region.
;;; The region delimiters BEG and END should be integers or markers.
;;;
;;; Only the fields that are external for all objects throughout
;;; the region are considered to be external ``in the region.''"
;;;   (save-excursion
;;;     (goto-char beg)
;;;     (let* ((equal t)
;;;            (fields (bongo-external-fields))
;;;            (values (bongo-get fields)))
;;;       (while (and (< (point) end) equal)
;;;         (unless (equal (bongo-get fields) values)
;;;           (setq equal nil))
;;;         (forward-line))
;;;       equal)))
;;;
;;; (defun bongo-external-fields-at-point-equal-to-previous-p (&optional point)
;;;   (if (bongo-point-at-first-line-p point)
;;;       (zerop (bongo-indentation-at-point point))
;;;     (bongo-external-fields-in-region-equal-p
;;;      (bongo-point-before-previous-line point)
;;;      (bongo-point-after-line point))))

(defun bongo-line-potential-external-fields (&optional point)
  "Return the fields of the line at POINT that could be external.
That is, return the names of the fields that are common between
  the line at POINT and the object line before that.
If the line at POINT is the first line, return nil."
  (unless (bongo-first-object-line-p point)
    (bongo-region-common-fields
     (bongo-point-before-previous-object-line point)
     (bongo-point-after-line point))))

(defun bongo-line-externalizable-fields (&optional point)
  "Return the externalizable fields of the line at POINT.
That is, return the names of all internal fields of the line at POINT
that could be made external without changing anything else."
  (set-difference (intersection
                   (bongo-line-proposed-external-fields point)
                   (bongo-line-potential-external-fields point))
                  (bongo-line-external-fields point)))

(defun bongo-line-redundant-header-p (&optional point)
  "Return non-nil if the line at POINT is a redundant header.
Redundant headers are headers whose internal fields are all externalizable."
  (and (bongo-header-line-p point)
       (bongo-set-equal-p (bongo-line-externalizable-fields point)
                          (bongo-line-internal-fields point))))

(defun bongo-backward-up-section ()
  (interactive)
  (let ((indentation (bongo-line-indentation)))
    (when (zerop indentation)
      (error "Already at the top level"))
    (bongo-backward-object-line)
    (while (>= (bongo-line-indentation) indentation)
      (unless (bongo-backward-object-line)
        (error "Broken sectioning")))))

(defun bongo-maybe-forward-object-line ()
  (interactive)
  (if (bongo-object-line-p) t
    (bongo-forward-object-line)))

(defun bongo-maybe-backward-object-line ()
  (interactive)
  (if (bongo-object-line-p) t
    (bongo-backward-object-line)))

(defun bongo-forward-section ()
  (interactive)
  (when (bongo-maybe-forward-object-line)
    (cond
     ((bongo-track-line-p)
      (bongo-forward-object-line))
     ((bongo-header-line-p)
      (goto-char (bongo-point-after-section))))))

(defun bongo-maybe-insert-intermediate-header ()
  "Make sure that the current line has a suitable header.
If the first outer header is too specific, split it in two."
  (when (bongo-line-indented-p)
    (let ((external-fields (bongo-line-external-fields)))
      (save-excursion
        (bongo-backward-up-section)
        (unless (bongo-set-equal-p
                 (bongo-line-external-fields-proposal)
                 external-fields)
          (bongo-insert-header external-fields)
          (bongo-externalize-fields))))))

(defun bongo-externalize-fields ()
  "Externalize as many fields of the current line as possible.
This function may create a new section header, but only by splitting an
existing header into two (see `bongo-maybe-insert-intermediate-header')."
  (with-bongo-buffer
    (unless (zerop (bongo-line-proposed-indentation))
      (let ((fields (bongo-line-externalizable-fields)))
        (when (> (length fields) (bongo-line-indentation))
          (bongo-line-set-external-fields fields)
          (bongo-maybe-insert-intermediate-header))))))


;;;; Backends

(defvar bongo-backends
  `((mpg123
     (default-matcher . ("mp3" "mp2"))
     (constructor . bongo-start-mpg123-player))
    (mplayer
     (default-matcher . ("mp3" "ogg" "wav" "wma"
                         "avi" "mpg" "asf" "wmv"))
     (constructor . bongo-start-mplayer-player)))
  "List of available Bongo player backends.
Entries are of the following form:
  (NAME (default-matcher . MATCHER)
        (constructor . CONSTRUCTOR)).

CONSTRUCTOR is a function that recieves one argument, FILE-NAME.
  It should immediately start a player for FILE-NAME.
MATCHER can be t, nil, a string, a list, or a symbol;
  see `bongo-file-name-matches-p' for more information.")

(defcustom bongo-preferred-backends nil
  "List of preferred Bongo player backends.
Entries are of the form (BACKEND-NAME . MATCHER).

BACKEND-NAME is the key for an entry in `bongo-backends'.
MATCHER, if non-nil, overrides the default matcher for the backend;
  see `bongo-file-name-matches-p' for more information."
  :type `(repeat
          (cons :tag "Preference"
                (choice :tag "Backend"
                        ,@(mapcar (lambda (x) `(const ,(car x)))
                                  bongo-backends)
                        symbol)
                (choice :tag "When"
                        (const :tag "Default condition for backend" nil)
                        (const :tag "Always preferred" t)
                        (radio :tag "Custom condition" :value ".*"
                               (regexp :tag "File name pattern")
                               (repeat :tag "File name extensions" string)
                               (function :tag "File name predicate")))))
  :group 'bongo)

(defun bongo-file-name-matches-p (file-name matcher)
  "Return non-nil if FILE-NAME matches MATCHER.
The possible values of MATCHER are listed below.

If it is t, return non-nil immediately.
If it is a string, treat it as a regular expression;
  return non-nil if FILE-NAME matches MATCHER.
If it is a symbol, treat it as a function name;
  return non-nil if (MATCHER FILE-NAME) returns non-nil.
If it is a list, treat it as a set of file name extensions;
  return non-nil if the extension of FILE-NAME appears in MATCHER.
Otherwise, signal an error."
  (cond
   ((eq t matcher) t)
   ((stringp matcher) (string-match matcher file-name))
   ((symbolp matcher) (funcall matcher file-name))
   ((listp matcher)
    (let ((extension (file-name-extension file-name)))
      (let (match)
        (while (and matcher (not match))
          (if (equal (car matcher) extension)
              (setq match t)
            (setq matcher (cdr matcher))))
        match)))
   (t (error "Bad file name matcher: %s" matcher))))

;;; XXX: These functions need to be refactored.

(defun bongo-track-file-name-regexp ()
  "Return a regexp matching the names of playable files.
Walk `bongo-preferred-backends' and `bongo-backends',
collecting file name regexps and file name extensions, and
construct a regexp that matches all of the possibilities."
  (let (extensions regexps)
    (let ((list bongo-preferred-backends))
      (while list
        (let ((backend (bongo-alist-get bongo-backends (caar list))))
          (when (null backend)
            (error "No such backend: `%s'" (caar list)))
          (let ((matcher (or (cdar list)
                             (bongo-alist-get backend 'default-matcher))))
            (cond
             ((stringp matcher)
              (setq regexps (cons matcher regexps)))
             ((listp matcher)
              (setq extensions (append matcher extensions))))))
        (setq list (cdr list))))
    (let ((list bongo-backends))
      (while list
        (let ((matcher (bongo-alist-get (cdar list) 'default-matcher)))
          (cond
           ((stringp matcher)
            (setq regexps (cons matcher regexps)))
           ((listp matcher)
            (setq extensions (append matcher extensions)))))
        (setq list (cdr list))))
    (when extensions
      (let ((regexp (format ".*\\.%s$" (regexp-opt extensions t))))
        (setq regexps (cons regexp regexps))))
    (if (null regexps) "."
      (mapconcat 'identity regexps "\\|"))))

(defun bongo-best-backend-for-file (file-name)
  "Return a backend that can play the file FILE-NAME, or nil.
First search `bongo-preferred-backends', then `bongo-backends'."
  (let ((best-backend nil))
    (let ((list bongo-preferred-backends))
      (while (and list (null best-backend))
        (let ((backend (bongo-alist-get bongo-backends (caar list))))
          (when (null backend)
            (error "No such backend: `%s'" (caar list)))
          (let ((matcher (or (cdar list)
                             (bongo-alist-get backend 'default-matcher))))
            (when (bongo-file-name-matches-p file-name matcher)
              (setq best-backend backend))))
        (setq list (cdr list))))
    (unless best-backend
      (let ((list bongo-backends))
        (while (and list (null best-backend))
          (let ((matcher (bongo-alist-get (cdar list) 'default-matcher)))
            (if (bongo-file-name-matches-p file-name matcher)
                (setq best-backend (cdar list))
              (setq list (cdr list)))))))
    best-backend))



(defcustom bongo-next-action 'bongo-play-next-or-stop
  "The function to call after the current track finishes playing."
  :type '(choice
          (const :tag "Stop playback" bongo-stop)
          (const :tag "Play the next track" bongo-play-next-or-stop)
          (const :tag "Play the same track again" bongo-replay-current)
          (const :tag "Play the previous track" bongo-play-previous)
          (const :tag "Play a random track" bongo-play-random))
  :group 'bongo)

(make-variable-buffer-local 'bongo-next-action)

(defun bongo-perform-next-action ()
  (interactive)
  (when bongo-next-action
    (funcall bongo-next-action)))

(defcustom bongo-renice-command "sudo renice"
  "The shell command to use in place of the `renice' program.
It will get three arguments: the priority, \"-p\", and the PID."
  :type 'string
  :group 'bongo)

(defun bongo-renice (pid priority)
  "Alter the priority of PID (process ID) to PRIORITY.
The variable `bongo-renice-command' says what command to use."
  (call-process shell-file-name nil nil nil shell-command-switch
                (format "%s %d -p %d" bongo-renice-command
                        priority pid)))


;;;; Players

(defvar bongo-player nil
  "The currently active player for this buffer, or nil.")
(make-variable-buffer-local 'bongo-player)

(defcustom bongo-player-started-hook '(bongo-show)
  "Normal hook run when a Bongo player is started."
  :options '(bongo-show)
  :type 'hook
  :group 'bongo)

(defvar bongo-player-started-functions nil
  "Abnormal hook run when a player is started.")
(defvar bongo-player-succeeded-functions nil
  "Abnormal hook run when a player exits normally.")
(defvar bongo-player-failed-functions nil
  "Abnormal hook run when a player exits abnormally.")
(defvar bongo-player-killed-functions nil
  "Abnormal hook run when a player recieves a fatal signal.")
(defvar bongo-player-finished-functions nil
  "Abnormal hook run when a player exits for whatever reason.")

(defun bongo-player-succeeded (player)
  "Run the hooks appropriate for when PLAYER has succeeded."
  (when (buffer-live-p (bongo-player-buffer player))
    (with-current-buffer (bongo-player-buffer player)
      (run-hook-with-args 'bongo-player-succeeded-functions player)
      (bongo-player-finished player))))

(defun bongo-player-failed (player)
  "Run the hooks appropriate for when PLAYER has failed."
  (let ((process (bongo-player-process player)))
    (message "Process `%s' exited abnormally with code %d"
             (process-name process) (process-exit-status process)))
  (when (buffer-live-p (bongo-player-buffer player))
    (with-current-buffer (bongo-player-buffer player)
      (run-hook-with-args 'bongo-player-failed-functions player)
      (bongo-player-finished player))))

(defun bongo-player-killed (player)
  "Run the hooks appropriate for when PLAYER was killed."
  (let ((process (bongo-player-process player)))
    (message "Process `%s' received fatal signal %s"
             (process-name process) (process-exit-status process)))
  (when (buffer-live-p (bongo-player-buffer player))
    (with-current-buffer (bongo-player-buffer player)
      (run-hook-with-args 'bongo-player-killed-functions player)
      (bongo-player-finished player))))

(defun bongo-player-finished (player)
  "Run the hooks appropriate for when PLAYER has finished.
Then perform the next action according to `bongo-next-action'.
You should not call this function directly."
  (when (buffer-live-p (bongo-player-buffer player))
    (with-current-buffer (bongo-player-buffer player)
      (run-hook-with-args 'bongo-player-finished-functions player)
      (bongo-perform-next-action))))

(defun bongo-play (file-name &optional backend-name)
  "Start playing FILE-NAME and return the new player.
In Bongo mode, first stop the currently active player, if any.

BACKEND-NAME specifies which backend to use; if it is nil,
Bongo will try to find the best player for FILE-NAME.

This function runs `bongo-player-started-hook'."
  (when (eq major-mode 'bongo-mode)
    (when bongo-player
      (bongo-player-stop bongo-player)))
  (let ((player (bongo-start-player file-name backend-name)))
    (prog1 player
      (when (eq major-mode 'bongo-mode)
        (setq bongo-player player))
      (run-hooks 'bongo-player-started-hook))))

(defcustom bongo-player-process-priority nil
  "The desired scheduling priority of Bongo player processes.
If set to a non-nil value, `bongo-renice' will be used to alter
the scheduling priority after a player process is started."
  :type '(choice (const :tag "Default" nil)
                 (const :tag "Slightly higher (-5)" -5)
                 (const :tag "Much higher (-10)" -10)
                 (const :tag "Very much higher (-15)" -15)
                 integer)
  :group 'bongo)

(defun bongo-start-player (file-name &optional backend-name)
  "Start and return a new Bongo player for FILE-NAME.

BACKEND-NAME specifies which backend to use; if it is nil,
Bongo will try to find the best player for FILE-NAME.

This function runs `bongo-player-started-functions'.
See also `bongo-play'."
  (let ((backend (if backend-name
                     (bongo-alist-get bongo-backends backend-name)
                   (bongo-best-backend-for-file file-name))))
    (when (null backend)
      (error "Don't know how to play `%s'" file-name))
    (let* ((player (funcall (bongo-alist-get backend 'constructor)
                            file-name))
           (process (bongo-player-process player)))
      (prog1 player
        (when (and process bongo-player-process-priority
                   (eq 'run (process-status process)))
          (bongo-renice (process-id process)
                        bongo-player-process-priority))
        (run-hook-with-args 'bongo-player-started-functions player)))))

(defun bongo-player-backend-name (player)
  "Return the name of PLAYER's backend (`mpg123', `mplayer', etc.)."
  (car player))

(defun bongo-player-get (player property)
  "Return the value of PLAYER's PROPERTY."
  (bongo-alist-get (cdr player) property))

(defun bongo-player-put (player property value)
  "Set PLAYER's PROPERTY to VALUE."
  (setcdr player (bongo-alist-put (cdr player) property value)))

(defun bongo-player-call (player method &rest arguments)
  "Call METHOD on PLAYER with extra ARGUMENTS."
  (apply (bongo-player-get player method) player arguments))

(defun bongo-player-process (player)
  "Return the process associated with PLAYER."
  (bongo-player-get player 'process))

(defun bongo-player-buffer (player)
  "Return the buffer associated with PLAYER."
  (bongo-player-get player 'buffer))

(defun bongo-player-file-name (player)
  "Return the name of the file played by PLAYER."
  (bongo-player-get player 'file-name))

(defun bongo-player-infoset (player)
  "Return the infoset for the file played by PLAYER."
  (bongo-infoset-from-file-name (bongo-player-file-name player)))

(defun bongo-player-show-infoset (player)
  "Display in the minibuffer what PLAYER is playing."
  (message (bongo-format-infoset (bongo-player-infoset player))))

(defun bongo-player-running-p (player)
  "Return non-nil if PLAYER's process is currently running."
  (eq 'run (process-status (bongo-player-process player))))

(defun bongo-player-explicitly-stopped-p (player)
  "Return non-nil if PLAYER was explicitly stopped."
  (bongo-player-get player 'explicitly-stopped))

(defun bongo-player-stop (player)
  "Tell PLAYER to stop playback completely.
When this function returns, PLAYER will no longer be usable."
  (bongo-player-put player 'explicitly-stopped t)
  (bongo-player-call player 'stop))

(defun bongo-player-pause/resume (player)
  "Tell PLAYER to toggle its paused state.
If PLAYER does not support pausing, signal an error."
  (bongo-player-call player 'pause/resume))

(defun bongo-player-seek-by (player n)
  "Tell PLAYER to seek to absolute position N.
If PLAYER does not support seeking, signal an error."
  (bongo-player-call player 'seek-by n))

(defun bongo-player-seek-to (player n)
  "Tell PLAYER to seek N units relative to the current position.
If PLAYER does not support seeking, signal an error."
  (bongo-player-call player 'seek-to n))

(defun bongo-player-elapsed-time (player)
  "Return the number of seconds PLAYER has played so far.
If the player backend cannot report this, return nil."
  (or (bongo-player-get player 'elapsed-time)
      (when (bongo-player-get player 'get-elapsed-time)
        (bongo-player-call player 'get-elapsed-time))))

(defun bongo-player-total-time (player)
  "Return the total number of seconds PLAYER has and will use.
If the player backend cannot report this, return nil."
  (or (bongo-player-get player 'total-time)
      (when (bongo-player-get player 'get-total-time)
        (bongo-player-call player 'get-total-time))))


;;;; Default implementations of player features

(defun bongo-default-player-stop (player)
  "Delete the process associated with PLAYER."
  (delete-process (bongo-player-process player)))

(defun bongo-default-player-pause/resume (player)
  "Signal an error explaining that PLAYER does not support pausing."
  (error "Pausing is not supported for %s"
         (bongo-player-backend-name player)))

(defun bongo-default-player-seek-by (player n)
  "Signal an error explaining that PLAYER does not support seeking."
  (error "Seeking is not supported for %s"
         (bongo-player-backend-name player)))

(defun bongo-default-player-seek-to (player n)
  "Signal an error explaining that PLAYER does not support seeking."
  (error "Seeking is not supported for %s"
         (bongo-player-backend-name player)))

(defun bongo-default-player-process-sentinel (process string)
  "If PROCESS has exited or been killed, run the appropriate hooks."
  (let ((status (process-status process))
        (player (bongo-process-get process 'bongo-player)))
    (cond
     ((eq status 'exit)
      (if (zerop (process-exit-status process))
          (bongo-player-succeeded player)
        (bongo-player-failed player)))
     ((eq status 'signal)
      (unless (bongo-player-explicitly-stopped-p player)
        (bongo-player-killed player))))))


;;;; The mpg123 backend

(defgroup bongo-mpg123 nil
  "The mpg123 backend."
  :group 'bongo)

(defcustom bongo-mpg123-program-name "mpg123"
  "The name of the mpg123-compatible executable."
  :type 'string
  :group 'bongo-mpg123)

(defcustom bongo-mpg123-device-type nil
  "The type of device (oss, alsa, esd, etc.) to be used by mpg123.
This corresponds to the `-o' option of mpg123."
  :type '(choice (const :tag "System default" nil)
                 (const :tag "ALSA" "alsa")
                 (const :tag "OSS" "oss")
                 (const :tag "Sun" "sun")
                 (const :tag "ESD" "esd")
                 (const :tag "ARTS" "arts")
                 (string :tag "Other (specify)"))
  :group 'bongo-mpg123)

(defcustom bongo-mpg123-device nil
  "The device (e.g., for ALSA, 1:0 or 2:1) to be used by mpg123.
This corresponds to the `-a' option of mpg123."
  :type '(choice (const :tag "System default" nil) string)
  :group 'bongo-mpg123)

(defcustom bongo-mpg123-interactive t
  "If non-nil, use the remote-control facility of mpg123.
Setting this to nil disables the pause and seek functionality."
  :type 'boolean
  :group 'bongo-mpg123)

(defun bongo-mpg123-is-mpg321-p ()
  "Return non-nil if the mpg123 program is actually mpg321."
  (string-match "^mpg321\\b" (shell-command-to-string
                              (concat bongo-mpg123-program-name
                                      " --version"))))

(defcustom bongo-mpg123-update-granularity
  (when (bongo-mpg123-is-mpg321-p) 30)
  "The number of frames to skip between each update from mpg321.
This corresponds to the mpg321-specific option --skip-printing-frames.
If your mpg123 does not support that option, set this variable to nil."
  :type '(choice (const :tag "None (lowest)" nil) integer)
  :group 'bongo-mpg123)

(defcustom bongo-mpg123-seek-increment 150
  "The step size (in frames) to use for relative seeking.
This is used by `bongo-mpg123-seek-by'."
  :type 'integer
  :group 'bongo-mpg123)

(defcustom bongo-mpg123-extra-arguments nil
  "Extra command-line arguments to pass to mpg123.
These will come at the end or right before the file name."
  :type '(repeat string)
  :group 'bongo-mpg123)

(defun bongo-mpg123-process-filter (process string)
  (let ((player (bongo-process-get process 'bongo-player)))
    (cond
     ((string-match "^@P 0$" string)
      (bongo-player-succeeded player)
      (set-process-sentinel process nil)
      (delete-process process))
     ((string-match "^@F .+ .+ \\(.+\\) \\(.+\\)$" string)
      (let* ((elapsed-time (string-to-number (match-string 1 string)))
             (total-time (+ elapsed-time (string-to-number
                                          (match-string 2 string)))))
        (bongo-player-put player 'elapsed-time elapsed-time)
        (bongo-player-put player 'total-time total-time))))))

(defun bongo-mpg123-player-interactive-p (player)
  "Return non-nil if PLAYER's process is interactive.
Interactive mpg123 processes support pausing and seeking."
  (bongo-alist-get player 'interactive-flag))

(defun bongo-mpg123-player-pause/resume (player)
  (if (bongo-mpg123-player-interactive-p player)
      (process-send-string (bongo-player-process player) "PAUSE\n")
    (error "This mpg123 process does not support pausing")))

(defun bongo-mpg123-player-seek-to (player position)
  (if (bongo-mpg123-player-interactive-p player)
      (process-send-string (bongo-player-process player)
                           (format "JUMP %d\n" position))
    (error "This mpg123 process does not support seeking")))

(defun bongo-mpg123-player-seek-by (player delta)
  (if (bongo-mpg123-player-interactive-p player)
      (process-send-string
       (bongo-player-process player)
       (format "JUMP %s%d\n" (if (< delta 0) "-" "+")
               (* bongo-mpg123-seek-increment (abs delta))))
    (error "This mpg123 process does not support seeking")))

(defun bongo-mpg123-player-get-elapsed-time (player)
  (bongo-player-get player 'elapsed-time))

(defun bongo-mpg123-player-get-total-time (player)
  (bongo-player-get player 'total-time))

(defun bongo-start-mpg123-player (file-name)
  (let* ((process-connection-type nil)
         (arguments (append
                     (when bongo-mpg123-device-type
                       (list "-o" bongo-mpg123-device-type))
                     (when bongo-mpg123-device
                       (list "-a" bongo-mpg123-device))
                     (when bongo-mpg123-update-granularity
                       (list "--skip-printing-frames"
                             (number-to-string
                              bongo-mpg123-update-granularity)))
                     bongo-mpg123-extra-arguments
                     (if bongo-mpg123-interactive
                         '("-R" "dummy") (list file-name))))
         (process (apply 'start-process "bongo-mpg123" nil
                         bongo-mpg123-program-name arguments))
         (player `(mpg123
                   (process . ,process)
                   (file-name . ,file-name)
                   (buffer . ,(current-buffer))
                   (stop . bongo-default-player-stop)
                   (interactive-flag . ,bongo-mpg123-interactive)
                   (pause/resume . bongo-mpg123-player-pause/resume)
                   (seek-by . bongo-mpg123-player-seek-by)
                   (seek-to . bongo-mpg123-player-seek-to))))
    (prog1 player
      (set-process-sentinel process 'bongo-default-player-process-sentinel)
      (bongo-process-put process 'bongo-player player)
      (if (not bongo-mpg123-interactive)
          (set-process-filter process 'ignore)
        (set-process-filter process 'bongo-mpg123-process-filter)
        (process-send-string process (format "LOAD %s\n" file-name))))))


;;;; The mplayer backend

(defgroup bongo-mplayer nil
  "The mplayer backend."
  :group 'bongo)

(defcustom bongo-mplayer-program-name "mplayer"
  "The name of the mplayer executable."
  :type 'string
  :group 'bongo-mplayer)

(defcustom bongo-mplayer-audio-device nil
  "The audio device to be used by mplayer.
This corresponds to the `-ao' option of mplayer."
  :type '(choice (const :tag "System default" nil)
                 string)
  :group 'bongo-mplayer)

(defcustom bongo-mplayer-video-device nil
  "The video device to be used by mplayer.
This corresponds to the `-vo' option of mplayer."
  :type '(choice (const :tag "System default" nil)
                 string)
  :group 'bongo-mplayer)

(defcustom bongo-mplayer-interactive t
  "If non-nil, use the slave mode of mplayer.
Setting this to nil disables the pause and seek functionality."
  :type 'boolean
  :group 'bongo-mplayer)

(defcustom bongo-mplayer-extra-arguments nil
  "Extra command-line arguments to pass to mplayer.
These will come at the end or right before the file name."
  :type '(repeat string)
  :group 'bongo-mplayer)

(defcustom bongo-mplayer-seek-increment 5.0
  "The step size (in seconds) to use for relative seeking.
This is used by `bongo-mplayer-seek-by'."
  :type 'float
  :group 'bongo-mplayer)

(defun bongo-mplayer-player-interactive-p (player)
  "Return non-nil if PLAYER's process is interactive.
Interactive mplayer processes support pausing and seeking."
  (bongo-alist-get player 'interactive-flag))

(defun bongo-mplayer-player-pause/resume (player)
  (if (bongo-mplayer-player-interactive-p player)
      (process-send-string (bongo-player-process player) "pause\n")
    (error "This mplayer process does not support pausing")))

(defun bongo-mplayer-player-seek-to (player position)
  (if (bongo-mpg123-player-interactive-p player)
      (process-send-string
       (bongo-player-process player)
       (format "seek %f 2\n" position))
    (error "This mplayer process does not support seeking")))

(defun bongo-mplayer-player-seek-by (player delta)
  (if (bongo-mplayer-player-interactive-p player)
      (process-send-string
       (bongo-player-process player)
       (format "seek %f 0\n" (* bongo-mplayer-seek-increment delta)))
    (error "This mplayer process does not support seeking")))

(defun bongo-start-mplayer-player (file-name)
  (let* ((process-connection-type nil)
         (arguments (append
                     (when bongo-mplayer-audio-device
                       (list "-ao" bongo-mplayer-audio-device))
                     (when bongo-mplayer-video-device
                       (list "-vo" bongo-mplayer-video-device))
                     bongo-mplayer-extra-arguments
                     (if bongo-mplayer-interactive
                         (list "-quiet" "-slave" file-name)
                       (list file-name))))
         (process (apply 'start-process "bongo-mplayer" nil
                         bongo-mplayer-program-name arguments))
         (player `(mplayer
                   (process . ,process)
                   (file-name . ,file-name)
                   (buffer . ,(current-buffer))
                   (stop . bongo-default-player-stop)
                   (interactive-flag . ,bongo-mplayer-interactive)
                   (pause/resume . bongo-mplayer-player-pause/resume)
                   (seek-by . bongo-mplayer-player-seek-by)
                   (seek-to . bongo-mplayer-player-seek-to))))
    (prog1 player
      (set-process-sentinel process 'bongo-default-player-process-sentinel)
      (bongo-process-put process 'bongo-player player))))


;;;; Controlling playback

(defun bongo-active-track-position ()
  "Return the character position of the active track, or nil."
  (marker-position overlay-arrow-position))

(defun bongo-set-active-track-position (&optional point)
  "Make the track on the line at POINT be the active track."
  (move-marker overlay-arrow-position (bongo-point-before-line point)))

(defun bongo-unset-active-track-position ()
  "Make it so that no track is active in this buffer."
  (move-marker overlay-arrow-position nil))

(defun bongo-line-active-track-p (&optional point)
  "Return non-nil if the line at POINT is the active track."
  (when (bongo-active-track-position)
    (and (>= (bongo-active-track-position)
             (bongo-point-before-line point))
         (< (bongo-active-track-position)
            (bongo-point-after-line point)))))

;;; (defun bongo-playing-p ()
;;;   "Return non-nil if there is an active player for this buffer."
;;;   (not (null bongo-player)))

(defun bongo-mouse-play-line (event)
  "Start playing the track that was clicked on."
  (interactive "e")
  (let ((posn (event-end event)))
    (with-current-buffer (window-buffer (posn-window posn))
      (bongo-play-line (posn-point posn)))))

(defun bongo-play-line (&optional point)
  "Start playing the track on the line at POINT.
If there is no track on the line at POINT, signal an error."
  (interactive)
  (if (not (bongo-track-line-p point))
      (error "No track at point")
    (bongo-set-active-track-position point)
    (let ((player (bongo-play (bongo-line-file-name point))))
      (bongo-line-set-property 'bongo-player player point))))

(defun bongo-replay-current (&optional non-immediate-p)
  "Play the current track from the start.
If NON-IMMEDIATE-P (prefix argument if interactive) is non-nil,
set `bongo-next-action' to `bongo-replay-current' and then return."
  (interactive "P")
  (with-bongo-buffer
    (when (null (bongo-active-track-position))
      (error "No active track"))
    (if non-immediate-p
        (setq bongo-next-action 'bongo-replay-current)
      (bongo-play-line (bongo-active-track-position)))))

(defun bongo-play-next (&optional non-immediate-p)
  "Start playing the next track in the current Bongo buffer.
If NON-IMMEDIATE-P (prefix argument if interactive) is non-nil,
set `bongo-next-action' to `bongo-play-next-or-stop' and then return."
  (interactive "P")
  (with-bongo-buffer
    (when (null (bongo-active-track-position))
      (error "No active track"))
    (if non-immediate-p
        (setq bongo-next-action 'bongo-play-next-or-stop)
      (let ((position (bongo-point-at-next-track-line
                       (bongo-active-track-position))))
        (if (null position)
            (error "No next track")
          (bongo-play-line position))))))

(defun bongo-play-next-or-stop (&optional non-immediate-p)
  "Maybe start playing the next track in the current Bongo buffer.
If there is no next track, stop playback.
If NON-IMMEDIATE-P (prefix argument if interactive) is non-nil,
set `bongo-next-action' to `bongo-play-next-or-stop' and then return."
  (interactive "P")
  (with-bongo-buffer
    (when (null (bongo-active-track-position))
      (error "No active track"))
    (if non-immediate-p
        (setq bongo-next-action 'bongo-play-next-or-stop)
      (let ((position (bongo-point-at-next-track-line
                       (bongo-active-track-position))))
        (when position
          (bongo-play-line position))))))

(defun bongo-play-previous (&optional non-immediate-p)
  "Start playing the previous track in the current Bongo buffer.
If NON-IMMEDIATE-P (prefix argument if interactive) is non-nil,
set `bongo-next-action' to `bongo-play-previous' and then return."
  (interactive "P")
  (with-bongo-buffer
    (when (null (bongo-active-track-position))
      (error "No active track"))
    (if non-immediate-p
        (setq bongo-next-action 'bongo-play-previous)
      (let ((position (bongo-point-at-previous-track-line
                       (bongo-active-track-position))))
        (if (null position)
            (error "No previous track")
          (bongo-play-line position))))))

(defun bongo-tracks-exist-p ()
  (let (tracks-exist)
    (save-excursion
      (goto-char (point-min))
      (while (and (not (eobp)) (not tracks-exist))
        (when (bongo-track-line-p)
          (setq tracks-exist t))
        (forward-line)))
    tracks-exist))

(defun bongo-play-random (&optional non-immediate-p)
  "Start playing a random track in the current Bongo buffer.
If NON-IMMEDIATE-P (prefix argument if interactive) is non-nil,
set `bongo-next-action' to `bongo-play-random' and then return."
  (interactive "P")
  (with-bongo-buffer
    (unless (bongo-tracks-exist-p)
      (error "No tracks"))
    (if non-immediate-p
        (setq bongo-next-action 'bongo-play-random)
      (save-excursion
        (goto-char (1+ (random (point-max))))
        (while (not (bongo-track-line-p))
          (goto-char (1+ (random (point-max)))))
        (bongo-play-line)))))

(defun bongo-stop (&optional non-immediate-p)
  "Permanently stop playback in the current Bongo buffer.
If NON-IMMEDIATE-P (prefix argument if interactive) is non-nil,
set `bongo-next-action' to `bongo-stop' and then return."
  (interactive "P")
  (with-bongo-buffer
    (if non-immediate-p
        (setq bongo-next-action 'bongo-stop)
      (when bongo-player
        (bongo-player-stop bongo-player))
      (bongo-unset-active-track-position))))

(defun bongo-pause/resume ()
  "Pause or resume playback in the current Bongo buffer.
This functionality may not be available for all backends."
  (interactive)
  (with-bongo-buffer
    (if bongo-player
        (bongo-player-pause/resume bongo-player)
      (error "No active player"))))

(defun bongo-seek-forward (&optional n)
  "Seek N units forward in the currently playing track.
The time units are currently backend-specific.
This functionality may not be available for all backends."
  (interactive "p")
  (with-bongo-buffer
    (if bongo-player
        (bongo-player-seek-by bongo-player n)
      (error "No active player"))))

(defun bongo-seek-backward (&optional n)
  "Seek N units backward in the currently playing track.
The time units are currently backend-specific.
This functionality may not be available for all backends."
  (interactive "p")
  (with-bongo-buffer
    (if bongo-player
        (bongo-player-seek-by bongo-player (- n))
      (error "No active player"))))


;;;; Inserting

(defun bongo-insert-line (&rest properties)
  "Insert a new line with PROPERTIES before the current line.
Externalize as many fields of the new line as possible and redisplay it.
Point is left immediately after the new line."
  (with-bongo-buffer
    (let ((inhibit-read-only t))
      (insert (apply 'propertize "\n" properties)))
    (forward-line -1)
    (bongo-externalize-fields)
    (if (bongo-empty-header-line-p)
        (bongo-delete-line)
      (bongo-redisplay-line)
      (forward-line))))

(defun bongo-insert-header (&optional fields)
  "Insert a new header line with internal FIELDS.
FIELDS defaults to the external fields of the current line."
  (bongo-insert-line 'bongo-header-p t 'bongo-fields
                     (or fields (bongo-line-external-fields))))

(defun bongo-insert-file (file-name)
  "Insert a new track line corresponding to FILE-NAME.
If FILE-NAME names a directory, call `bongo-insert-directory'."
  (interactive (list (expand-file-name
                      (read-file-name "Insert track: "
                                      default-directory nil t
                                      (when (eq major-mode 'dired-mode)
                                        (dired-get-filename t))))))
  (if (file-directory-p file-name)
      (bongo-insert-directory file-name)
    (bongo-insert-line 'bongo-file-name file-name)
    (when (and (interactive-p) (not (eq major-mode 'bongo-mode)))
      (message "Inserted track `%s'"
               (bongo-format-infoset
                (bongo-infoset-from-file-name file-name))))))

(defun bongo-insert-directory (directory-name)
  "Insert a new track line for each file in DIRECTORY-NAME.
Only insert files that can be played by some backend, as determined
by the file name (see `bongo-track-file-name-regexp').
Do not examine subdirectories of DIRECTORY-NAME."
  (interactive (list (expand-file-name
                      (read-directory-name
                       "Insert directory: " default-directory nil t
                       (when (eq major-mode 'dired-mode)
                         (when (file-directory-p (dired-get-filename))
                           (dired-get-filename t)))))))
  (when (not (file-directory-p directory-name))
    (error "File is not a directory: %s" directory-name))
;;;   (when (file-exists-p (concat directory-name "/cover.jpg")))
  (let ((file-names (directory-files directory-name t
                                     (bongo-track-file-name-regexp))))
    (when (null file-names)
      (error "Directory contains no playable files"))
    (dolist (file-name file-names)
      (bongo-insert-file file-name))
    (when (and (interactive-p) (not (eq major-mode 'bongo-mode)))
      (message "Inserted %d files" (length file-names)))))

(defun bongo-insert-directory-tree (directory-name)
  "Insert a new track line for each file below DIRECTORY-NAME.
Only insert files that can be played by some backend, as determined
by the file name (see `bongo-track-file-name-regexp').

This function descends each subdirectory of DIRECTORY-NAME recursively,
using `bongo-gnu-find-program' to find the files."
  (interactive (list (expand-file-name
                      (read-directory-name
                       "Insert directory tree: "
                       default-directory nil t
                       (when (eq major-mode 'dired-mode)
                         (when (file-directory-p (dired-get-filename))
                           (dired-get-filename t)))))))
  (let ((file-count 0))
    (with-temp-buffer
      (apply 'call-process bongo-gnu-find-program nil t nil
             directory-name "-type" "f"
             "-iregex" (bongo-track-file-name-regexp)
             bongo-gnu-find-extra-arguments)
      (sort-lines nil (point-min) (point-max))
      (goto-char (point-min))
      (while (not (eobp))
        (bongo-insert-file (buffer-substring (point) (point-at-eol)))
        (setq file-count (1+ file-count))
        (forward-line)))
    (when (zerop file-count)
      (error "Directory tree contains no playable files"))
    (when (and (interactive-p) (not (eq major-mode 'bongo-mode)))
      (message "Inserted %d files" file-count))))


;;;; Joining/splitting

(defun bongo-join-region (beg end &optional fields)
  "Join all tracks between BEG and END by externalizing FIELDS.
If FIELDS is nil, externalize all common fields between BEG and END.
If there are no common fields, or the fields are already external,
  or the region contains less than two lines, signal an error.
This function creates a new header if necessary."
  (interactive "r")
  (when (null fields)
    (unless (setq fields (bongo-region-common-fields beg end))
      (error "Cannot join tracks: no common fields")))
  (when (= 0 (bongo-region-line-count beg end))
    (error "Cannot join tracks: region empty"))
  (when (bongo-region-fields-external-p beg end fields)
    (error "Cannot join tracks: already joined"))
  (when (= 1 (bongo-region-line-count beg end))
    (error "Cannot join tracks: need more than one"))
  (save-excursion
    (setq end (move-marker (make-marker) end))
    (goto-char beg)
    (beginning-of-line)
    (let ((indent (length fields)))
      (while (< (point) end)
        (when (< (bongo-line-indentation) indent)
          (bongo-line-set-external-fields fields))
        (bongo-forward-object-line)))
    (move-marker end nil)
;;;     (when (bongo-line-redundant-header-p)
;;;       (bongo-delete-line))
    (goto-char beg)
    (bongo-insert-header)))

(defun bongo-join (&optional skip)
  "Join the fields around point or in the region.
If Transient Mark mode is enabled, delegate to `bongo-join-region'.
Otherwise, find all common fields at point, and join all tracks around
point that share those fields.  (See `bongo-common-fields-at-point'.)

If SKIP is nil, leave point at the newly created header line.
If SKIP is non-nil, leave point at the first object line after
  the newly created section.
If there are no common fields at point and SKIP is nil, signal an error.
If called interactively, SKIP is always non-nil."
  (interactive "p")
  (if (and transient-mark-mode mark-active)
      (bongo-join-region (region-beginning) (region-end))
    (let ((fields (bongo-common-fields-at-point)))
      (if (null fields)
          (if (not skip)
              (error "No common fields at point")
            (unless (bongo-last-object-line-p)
              (bongo-forward-object-line)))
        (let ((values (bongo-line-field-values fields))
              (before (bongo-point-before-line))
              (after (bongo-point-after-line)))
          (save-excursion
            (while (and (bongo-backward-object-line)
                        (equal values (bongo-line-field-values fields)))
              (setq before (bongo-point-before-line))))
          (save-excursion
            (while (and (bongo-forward-object-line)
                        (equal values (bongo-line-field-values fields)))
              (setq after (bongo-point-after-line))))
          (setq after (move-marker (make-marker) after))
          (bongo-join-region before after fields)
          (when skip (goto-char after))
          (move-marker after nil)
          (bongo-maybe-forward-object-line))))))

(defun bongo-split (&optional skip)
  "Split the section below the header line at point.
If point is not on a header line, split the section at point.

If SKIP is nil, leave point at the first object in the section.
If SKIP is non-nil, leave point at the first object after the section.
If point is neither on a header line nor in a section,
  and SKIP is nil, signal an error.
If called interactively, SKIP is always non-nil."
  (interactive "p")
  (when (not (bongo-object-line-p))
    (bongo-backward-object-line))
  (when (not (bongo-object-line-p))
    (error "No bongo object here"))
  (when (and (bongo-track-line-p) (bongo-line-indented-p))
    (bongo-backward-up-section))
  (if (bongo-track-line-p)
      (if (not skip)
          (error "No section here")
        (unless (bongo-last-object-line-p)
          (bongo-forward-object-line)))
    (let ((fields (bongo-line-internal-fields))
          (end (move-marker (make-marker) (bongo-point-after-section))))
      (bongo-delete-line)
      (let ((start (point)))
        (while (< (point) end)
          (let ((previous (point)))
            (bongo-forward-section)
            (bongo-line-set-external-fields
             (set-difference (bongo-line-external-fields previous) fields)
             previous)))
        (move-marker end nil)
        (when (not skip)
          (goto-char start))
        (bongo-maybe-forward-object-line)))))


;;;; Displaying

(defun bongo-redisplay-line ()
  "Redisplay the current line, preserving semantic text properties."
  (let ((inhibit-read-only t)
        (indentation (bongo-line-indentation))
        (infoset (bongo-line-internal-infoset))
        (header-p (bongo-header-line-p))
        (properties (bongo-line-get-semantic-properties)))
    (save-excursion
      (bongo-clear-line)
      (dotimes (_ indentation) (insert bongo-indentation-string))
      (let ((content (bongo-format-infoset infoset)))
        (insert (if (not header-p) content
                  (bongo-format-header content))))
      (bongo-line-set-properties properties)
;;;       (bongo-line-set-property 'face (if header-p 'bongo-header
;;;                                        'bongo-track))
      )))

(defun bongo-redisplay (&optional arg)
  "Redisplay every line in the entire buffer.
With prefix argument, remove all indentation and headers."
  (interactive "P")
  (save-excursion
    (with-bongo-buffer
      (message "Rendering buffer...")
      (goto-char (point-min))
      (bongo-maybe-forward-object-line)
      (while (not (eobp))
        (cond
         ((and arg (bongo-header-line-p))
          (bongo-delete-line)
          (bongo-maybe-forward-object-line))
         ((and arg (bongo-track-line-p))
          (bongo-line-set-external-fields nil)
          (bongo-forward-object-line))
         ((bongo-object-line-p)
          (bongo-redisplay-line)
          (bongo-forward-object-line))))
      (message "Rendering buffer...done"))))

(defun bongo-recenter ()
  "Move point to the currently playing track and recenter.
If no track is currently playing, just call `recenter'."
  (interactive)
  (bongo-goto-point (bongo-active-track-position))
  (recenter))


;;;; Killing/yanking

(defun bongo-kill-line (&optional arg)
  "In Bongo, kill the current line.
With prefix argument, kill that many lines from point.
See `kill-line'."
  (interactive "P")
  (let ((inhibit-read-only t))
    (cond
     ((bongo-track-line-p)
      (when (bongo-line-active-track-p)
        (bongo-unset-active-track-position))
      (let ((kill-whole-line t))
        (beginning-of-line)
        (kill-line arg)))
     ((bongo-header-line-p)
      (kill-region (bongo-point-before-line)
                   (bongo-point-after-section)))
     (t
      (kill-line arg)))
;;;     (when (bongo-redundant-header-at-point-p)
;;;       (bongo-delete-line))
    ))

(defun bongo-kill-region (&optional beg end)
  "In Bongo, kill the lines between point and mark.
See `kill-region'."
  (interactive "r")
  (setq end (move-marker (make-marker) end))
  (save-excursion
    (goto-char beg)
    (bongo-kill-line)
    (while (< (point) end)
      (append-next-kill)
      (bongo-kill-line)))
  (move-marker end nil))

(defun bongo-format-seconds (n)
  "Return a user-friendly string representing N seconds.
If N < 3600, the string will look like \"mm:ss\".
Otherwise, it will look like \"hhh:mm:ss\", the first field
being arbitrarily long."
  (setq n (floor n))
  (let ((hours (/ n 3600))
        (minutes (% (/ n 60) 60))
        (seconds (% n 60)))
    (let ((result (format "%02d:%02d" minutes seconds)))
      (unless (zerop hours)
        (setq result (format "%d:%s" hours result)))
      result)))

(defun bongo-show (&optional arg)
  "Display what Bongo is playing in the minibuffer.
With prefix argument, insert the description at point."
  (interactive "P")
  (let (player infoset)
    (with-bongo-buffer
      (setq player bongo-player)
      (let ((position (bongo-active-track-position)))
        (when (null position)
          (error "No track is currently playing"))
        (setq infoset (bongo-line-infoset position))))
    (let ((elapsed-time (when player (bongo-player-elapsed-time player)))
          (total-time (when player (bongo-player-total-time player)))
          (description (bongo-format-infoset infoset)))
      (let ((string (if (not (and elapsed-time total-time))
                        description
                      (format "%s [%s/%s]" description
                              (bongo-format-seconds elapsed-time)
                              (bongo-format-seconds total-time)))))
        (if arg (insert string)
          (message string))))))

(defun bongo-yank (&optional arg)
  "In Bongo, reinsert the last sequence of killed lines.
See `yank'."
  (interactive "P")
  (let ((inhibit-read-only t))
    (beginning-of-line)
    (yank arg)
    (let ((beg (region-beginning))
          (end (move-marker (make-marker) (region-end))))
      (save-excursion
        (goto-char beg)
        (when (not (bongo-object-line-p))
          (bongo-forward-object-line))
        (while (and (< (point) end))
          (let ((player (bongo-line-get-property 'bongo-player)))
            (when player
              (if (and (eq player bongo-player)
                       (null (bongo-active-track-position)))
                  (bongo-set-active-track-position (point-at-bol))
                (bongo-line-remove-property 'bongo-player))))
          (bongo-forward-object-line))
        ;; These headers will stay if they are needed,
        ;; or disappear automatically otherwise.
        (goto-char end)
        (unless (bongo-last-object-line-p)
          (bongo-insert-header))
        (goto-char beg)
        (bongo-insert-header)
        ;; In case the upper header does disappear,
        ;; we need to merge backwards to connect.
        (when (not (bongo-object-line-p))
          (bongo-forward-object-line))
        (when (< (point) end)
          (bongo-externalize-fields))
        (move-marker end nil)))))

;; XXX: This definitely does not work properly.
(defun bongo-yank-pop (&optional arg)
  "In Bongo, replace the just-yanked lines with different ones.
See `yank-pop'."
  (interactive "P")
  (let ((inhibit-read-only t))
    (yank-pop arg)
    (bongo-externalize-fields)))

;; XXX: This probably does not work properly.
(defun bongo-undo (&optional arg)
  "In Bongo, undo some previous changes.
See `undo'."
  (interactive "P")
  (let ((inhibit-read-only t))
    (undo arg)))


;;;; Serializing buffers

;;; (defun bongo-parse-header ()
;;;   "Parse a Bongo header.
;;; Leave point immediately after the header."
;;;   (let (pairs)
;;;     (while (looking-at "\\([a-zA-Z-]+\\): \\(.*\\)")
;;;       (setq pairs (cons (cons (intern (downcase (match-string 1)))
;;;                               (match-string 2))
;;;                         pairs))
;;;       (forward-line))
;;;     pairs))

(defvar bongo-magic-string
  "Content-Type: application/x-bongo\n"
  "The string that identifies serialized Bongo buffers.
This string will inserted when serializing buffers.")

(defvar bongo-magic-regexp
  "Content-Type: application/x-bongo\\(-playlist\\)?\n"
  "Regexp that matches at the start of serialized Bongo buffers.
Any file whose beginning matches this regexp will be assumed to be
a serialized Bongo buffer.")

(add-to-list 'auto-mode-alist '("\\.bongo$" . bongo-mode))
(add-to-list 'format-alist
             (list 'bongo "Serialized Bongo buffer"
                   bongo-magic-string 'bongo-decode
                   'bongo-encode t nil))

(defun bongo-decode (beg end)
  "Convert a serialized Bongo buffer into the real thing.
Modify region between BEG and END; return the new end of the region.

This function is used when loading Bongo buffers from files.
You probably do not want to call this function directly;
instead, use high-level functions such as `find-file'."
  (save-excursion
    (save-restriction
      (narrow-to-region beg end)
      (goto-char (point-min))
      (unless (looking-at bongo-magic-regexp)
        (error "Unrecognized format"))
      (bongo-delete-line)
      (while (not (eobp))
        (let ((start (point)))
          (condition-case nil
              (let ((object (read (current-buffer))))
                (delete-region start (point))
                (if (stringp object) (insert object)
                  (error "Unexpected object: %s" object)))
            (end-of-file
             (delete-region start (point-max))))))
      (save-restriction
        (widen)
        (goto-char beg)
        (let ((case-fold-match t))
          (when (and (bobp) (not (looking-at ".* -\\*- *Bongo *-\\*-")))
            (insert-char #x20 (- fill-column (length "-*- Bongo -*-") 1))
            (insert "-*- Bongo -*-\n")
            (forward-line -1)
            (put-text-property (point-at-bol) (point-at-eol)
                               'face 'bongo-comment))))
      (point-max))))

(defvar bongo-line-serializable-properties
  (list 'face 'bongo-file-name 'bongo-header-p
        'bongo-fields 'bongo-external-fields)
  "List of serializable text properties used in Bongo buffers.
When a bongo Buffer is written to a file, only serializable text
properties are saved; all other text properties are discarded.")

(defun bongo-encode (beg end buffer)
  "Serialize part of a Bongo buffer into a flat representation.
Modify region between BEG and END; return the new end of the region.

This function is used when writing Bongo buffers to files.
You probably do not want to call this function directly;
instead, use high-level functions such as `save-buffer'."
  (save-excursion
    (save-restriction
      (narrow-to-region beg end)
      (bongo-ensure-final-newline)
      (goto-char (point-min))
      (when (re-search-forward " *-\\*- *Bongo *-\\*-\n?" nil t)
        (replace-match ""))
      (goto-char (point-min))
      (insert bongo-magic-string "\n")
      (while (not (eobp))
        (bongo-keep-text-properties (point-at-bol) (point-at-eol) '(face))
        (bongo-keep-text-properties (point-at-eol) (1+ (point-at-eol))
                                    bongo-line-serializable-properties)
        (prin1 (bongo-extract-line) (current-buffer))
        (insert "\n")))))



(defun bongo-quit ()
  "Quit Bongo by selecting some other buffer."
  (interactive)
  (switch-to-buffer (other-buffer (current-buffer))))

(defun bongo-mode ()
  "Major mode for Bongo buffers."
  (interactive)
  (let ((arrow-position
         (when (local-variable-p 'overlay-arrow-position)
           overlay-arrow-position)))
    (kill-all-local-variables)
    (set (make-local-variable 'overlay-arrow-position)
         (or arrow-position (make-marker))))
  (use-local-map bongo-mode-map)
  (setq buffer-read-only t)
  (setq major-mode 'bongo-mode)
  (setq mode-name "Bongo")
  (setq buffer-file-format '(bongo))
  (run-mode-hooks 'bongo-mode-hook))

(defvar bongo-mode-map
  (let ((map (make-sparse-keymap)))
    (suppress-keymap map)
    (define-key map "\C-m" 'bongo-play-line)
    (define-key map [mouse-2] 'bongo-mouse-play-line)
    (define-key map "q" 'bongo-quit)
    (define-key map "Q" 'bury-buffer)
    (define-key map "g" 'bongo-redisplay)
    (define-key map "l" 'bongo-recenter)
    (define-key map "j" 'bongo-join)
    (define-key map "J" 'bongo-split)
    (define-key map "k" 'bongo-kill-line)
    (substitute-key-definition
     'kill-line 'bongo-kill-line map global-map)
    (define-key map "w" 'bongo-kill-region)
    (substitute-key-definition
     'kill-region 'bongo-kill-region map global-map)
    (define-key map "y" 'bongo-yank)
    (substitute-key-definition
     'yank 'bongo-yank map global-map)
    (substitute-key-definition
     'yank-pop 'bongo-yank-pop map global-map)
    (substitute-key-definition
     'undo 'bongo-undo map global-map)
    (define-key map " " 'bongo-pause/resume)
    (define-key map "s" 'bongo-stop)
    (define-key map "p" 'bongo-play-previous)
    (define-key map "n" 'bongo-play-next)
    (define-key map "r" 'bongo-play-random)
    (define-key map "N" 'bongo-perform-next-action)
    (define-key map "f" 'bongo-seek-forward)
    (define-key map "b" 'bongo-seek-backward)
    (when (require 'volume nil t)
      (define-key map "v" 'volume))
    (define-key map "if" 'bongo-insert-file)
    (define-key map "id" 'bongo-insert-directory)
    (define-key map "it" 'bongo-insert-directory-tree)
    map))

(defmacro with-bongo-buffer (&rest body)
  "Execute the forms in BODY in some Bongo buffer.
The value returned is the value of the last form in BODY.

If the current buffer is a Bongo buffer, don't switch buffers.
Otherwise, switch to the default Bongo buffer.  (See the
function `bongo-default-buffer'.)"
  (declare (indent 0) (debug t))
  `(with-current-buffer
       (if (bongo-buffer-p) (current-buffer)
         (bongo-default-buffer))
     ,@body))

(defvar bongo-default-buffer nil
  "The default Bongo buffer, or nil.
Bongo commands will operate on this buffer when executed from
buffers that are not in Bongo mode.

This variable overrides `bongo-default-buffer-name'.
See the function `bongo-default-buffer'.")

(defun bongo-buffer-p (&optional buffer)
  "Return non-nil if BUFFER is in Bongo mode.
If BUFFER is nil, test the current buffer instead."
  (with-current-buffer (or buffer (current-buffer))
    (eq 'bongo-mode major-mode)))

(defun bongo-default-buffer ()
  "Return the default Bongo buffer.

If the variable `bongo-default-buffer' is non-nil, return that.
Otherwise, return the most recently selected Bongo buffer.
If there is no buffer in Bongo mode, create one.  The name of
the new buffer will be the value of `bongo-default-buffer-name'."
  (or bongo-default-buffer
      (let (result (list (buffer-list)))
        (while (and list (not result))
          (when (bongo-buffer-p (car list))
            (setq result (car list)))
          (setq list (cdr list)))
        result)
      (let ((buffer (get-buffer-create bongo-default-buffer-name)))
        (prog1 buffer
          (with-current-buffer buffer
            (bongo-mode))))))

(defun bongo ()
  "Switch to the default Bongo buffer.
See `bongo-default-buffer'."
  (interactive)
  (switch-to-buffer (bongo-default-buffer)))

(provide 'bongo)
