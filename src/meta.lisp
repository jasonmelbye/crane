(in-package :cl-user)
(defpackage crane.meta
  (:use :cl :anaphora :iter)
  (:import-from :crane.connect
                :database-type
                :get-db)
  (:export :<table-class>
           :table-name
           :abstractp
           :deferredp
           :table-database
           :col-type
           :col-null-p
           :col-unique-p
           :col-primary-p
           :col-index-p
           :col-foreign
           :col-autoincrement-p
           :col-check
           :digest
           :diff-digest)
  (:documentation "This file defines the metaclasses that map CLOS objects to SQL tables, and some basic operations on them."))
(in-package :crane.meta)

(defclass <table-class> (closer-mop:standard-class)
  ((abstractp :reader abstractp
              :initarg :abstractp
              :initform nil
              :documentation "Whether the class corresponds to an SQL table or not.")
   (deferredp :reader deferredp
              :initarg :deferredp
              :initform nil
              :documentation "Whether the class should be built only when explicitly calling build.")
   (database :reader %table-database
             :initarg :database
             :initform nil
             :documentation "The database this class belongs to."))
  (:documentation "A table metaclass."))

(defmethod table-name ((class <table-class>))
  "Return the name of a the class, a symbol."
  (class-name class))

(defmethod table-database ((class <table-class>))
  "The database this class belongs to."
  (aif (%table-database class)
       it
       crane.connect:*default-db*))

(defmethod closer-mop:validate-superclass ((class <table-class>)
                                           (super closer-mop:standard-class))
  t)

(defmethod closer-mop:validate-superclass ((class standard-class)
                                           (super <table-class>))
  t)

(defclass table-class-slot-definition-mixin ()
  ((col-type :initarg :col-type
             :accessor col-type)
   (col-null-p :initarg :col-null-p
               :reader  col-null-p)
   (col-unique-p :initarg :col-unique-p
                 :reader  col-unique-p)
   (col-primary-p :initarg :col-primary-p
                  :reader col-primary-p)
   (col-index-p :initarg :col-index-p
                :reader  col-index-p)
   (col-foreign :initarg :col-foreign
                :reader  col-foreign)
   (col-autoincrement-p :initarg :col-autoincrement-p
                        :reader  col-autoincrement-p)
   (col-check :initarg :col-check
              :reader col-check)))

(defclass table-class-direct-slot-definition (table-class-slot-definition-mixin
                                              closer-mop:standard-direct-slot-definition)
  ((col-null-p :initform t)
   (col-unique-p :initform nil)
   (col-primary-p :initform nil)
   (col-index-p :initform nil)
   (col-foreign :initform nil)
   (col-autoincrement-p :initform nil)
   (col-check :initarg nil)))

(defclass table-class-effective-slot-definition (table-class-slot-definition-mixin
                                                 closer-mop:standard-effective-slot-definition)
  ())

;;; Common Lisp is a vast ocean of possibilities, stretching infinitely
;;; and with no horizon... And here I am pretending to understand
;;; the MOP while trying not to end up in r/badcode, like a child
;;; playing in the surf...

(defmethod closer-mop:direct-slot-definition-class ((class <table-class>) &rest initargs)
  (declare (ignore class initargs))
  (find-class 'table-class-direct-slot-definition))

(defmethod closer-mop:effective-slot-definition-class ((class <table-class>) &rest initargs)
  (declare (ignore class initargs))
  (find-class 'table-class-effective-slot-definition))

(defmethod closer-mop:compute-effective-slot-definition ((class <table-class>)
                                                         slot-name direct-slot-definitions)
  (declare (ignore slot-name))
  (let ((effective-slot-definition (call-next-method)))
    (setf (slot-value effective-slot-definition 'col-type)
          (col-type (first direct-slot-definitions))

          (slot-value effective-slot-definition 'col-null-p)
          (col-null-p (first direct-slot-definitions))

          (slot-value effective-slot-definition 'col-unique-p)
          (col-unique-p (first direct-slot-definitions))

          (slot-value effective-slot-definition 'col-primary-p)
          (if (and (eq (database-type (get-db (table-database class)))
                       :sqlite3)
                   (eq (col-autoincrement-p (first direct-slot-definitions))
                       t))
              nil
              (col-primary-p (first direct-slot-definitions)))

          (slot-value effective-slot-definition 'col-index-p)
          (col-index-p (first direct-slot-definitions))

          (slot-value effective-slot-definition 'col-foreign)
          (col-foreign (first direct-slot-definitions))

          (slot-value effective-slot-definition 'col-autoincrement-p)
          (col-autoincrement-p (first direct-slot-definitions))

          (slot-value effective-slot-definition 'col-check)
          (if (slot-boundp (first direct-slot-definitions) 'col-check)
              (col-check (first direct-slot-definitions))
              nil))
    effective-slot-definition))

(defun digest-slot (slot)
  (list :name (closer-mop:slot-definition-name slot)
        :type (col-type slot)
        :nullp (col-null-p slot)
        :uniquep (col-unique-p slot)
        :primaryp (col-primary-p slot)
        :indexp (col-index-p slot)
        :check (col-check slot)
        :autoincrementp (col-autoincrement-p slot)
        :foreign (col-foreign slot)))

(defmethod digest ((class <table-class>))
  "Serialize a class's options and slots' options into a plist"
  (list :table-options
        (list :database (table-database class))
        :columns
        (let ((slots (closer-mop:class-slots class)))
          (if slots
              (mapcar #'digest-slot
                      (closer-mop:class-slots class))
              (error 'crane.errors:empty-table
                     :text "The table ~A has no slots."
                     (table-name class))))))

(defun diff-slot (slot-a slot-b)
  "Compute the difference between two slot digests.
See DIGEST."
  (append (list :name (getf slot-a :name) :diff)
          (list
           (crane.util:diff-plist slot-a slot-b :test #'equal))))

(defun sort-slot-list (list)
  list)

(defun diff-digest (digest-a digest-b)
  "Compute the difference between two digests.
See DIGEST."
  (flet ((find-slot-definition (slot-name digest)
           (iter (for slot in (getf digest :columns))
             (if (eql slot-name (getf slot :name))
                 (return slot)))))
    (let* ((slot-names-a
             (iter (for slot in (getf digest-a :columns))
               (collecting (getf slot :name))))
           (slot-names-b
             (iter (for slot in (getf digest-b :columns))
               (collecting (getf slot :name))))
           (changes
             (intersection slot-names-a slot-names-b))
           (additions
             (set-difference slot-names-b slot-names-a))
           (deletions
             (set-difference slot-names-a slot-names-b))
           (changes-a
             (iter (for slot-name in changes)
               (collecting (find-slot-definition slot-name digest-a))))
           (changes-b
             (iter (for slot-name in changes)
               (collecting (find-slot-definition slot-name digest-b)))))
      (list :additions (mapcar #'(lambda (slot-name)
                                   (find-slot-definition slot-name digest-b))
                               (remove-if #'null additions))
            :deletions (remove-if #'null deletions)
            :changes
            (remove-if-not #'(lambda (slot) (getf slot :diff))
                           (remove-if #'null
                                      (mapcar #'diff-slot
                                              (sort-slot-list changes-a)
                                              (sort-slot-list changes-b))))))))
