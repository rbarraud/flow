#|
 This file is a part of flow
 (c) 2017 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.flow)

(defun visit (node function)
  (let ((visited (make-hash-table :test 'eq)))
    (labels ((%visit (node)
               (unless (gethash node visited)
                 (setf (gethash node visited) node)
                 (funcall function node)
                 (dolist (connection (connections node))
                   (cond ((eql node (node (left connection)))
                          (%visit (node (right connection))))
                         ((eql node (node (right connection)))
                          (%visit (node (left connection)))))))))
      (%visit node))))

(defun extract-graph (node)
  (let ((vertices ())
        (edges ()))
    (flet ((connect (left right)
             (pushnew (list left right) edges :test #'equal)))
      (visit node (lambda (node)
                    (push node vertices)
                    (dolist (connection (connections node))
                      (etypecase connection
                        (directed-connection
                         (connect (node (left connection)) (node (right connection))))
                        (connection
                         (connect (node (left connection)) (node (right connection)))
                         (connect (node (right connection)) (node (left connection))))))))
      (values vertices edges))))

(defun topological-sort (node)
  (let ((sorted ())
        (visited (make-hash-table :test 'eq)))
    (labels ((%visit (node)
               (case (gethash node visited)
                 (:temporary
                  (error "The graph contains cycles."))
                 (:permanently)
                 ((NIL)
                  (setf (gethash node visited) :temporary)
                  (dolist (connection (connections node))
                    (etypecase connection
                      (directed-connection
                       (when (eql node (left connection))
                         (%visit (right connection))))
                      (connection
                       (cond ((eql node (left connection))
                              (%visit (right connection)))
                             ((eql node (right connection))
                              (%visit (left connection)))))))
                  (setf (gethash node visited) :permanently)
                  (push node sorted)))))
      (%visit node))
    sorted))

(defun color-graph (vertices edges &key (attribute :color) (clear T))
  (let ((colors (make-array (length vertices) :initial-element :available)))
    (flet ((mark-adjacent (vertex how)
             (loop for (from to) in edges
                   do (cond ((eql vertex from)
                             (let ((color (attribute to attribute)))
                               (when color (setf (aref colors color) how))))
                            ((eql vertex to)
                             (let ((color (attribute from attribute)))
                               (when color (setf (aref colors color) how))))))))
      (when clear
        (dolist (vertex vertices)
          (remove-attribute vertex attribute)))
      (dolist (vertex vertices vertices)
        (mark-adjacent vertex :unavailable)
        (setf (attribute vertex attribute) (position :available colors))
        (mark-adjacent vertex :available)))))

(defun color-nodes (node &key (attribute :color) (clear T))
  (multiple-value-bind (vertices edges)
      (extract-graph node)
    (color-graph vertices edges :attribute attribute :clear clear)))

(defun allocate-ports (node &key (attribute :color) (clear T))
  (flet ((color (port) (attribute port attribute))
         ((setf color) (value port) (setf (attribute port attribute) value)))
    (let ((nodes (topological-sort node))
          (length 0))
      (print nodes)
      ;; Clear and count number of ports
      (dolist (node nodes nodes)
        (dolist (port (ports node))
          (unless (typep port 'in-port)
            (incf length))
          (when clear (setf (color port) NIL))))
      ;; Perform the actual colouring
      (let ((colors (make-array length :initial-element :available)))
        (flet ((mark-adjacent (node how)
                 (dolist (connection (connections node))
                   (cond ((eql node (node (right connection)))
                          (when (color (left connection))
                            (setf (aref colors (color (left connection))) how)))
                         ((eql node (node (left connection)))
                          (when (color (right connection))
                            (setf (aref colors (color (right connection))) how)))))))
          (dolist (node nodes nodes)
            (mark-adjacent node :unavailable)
            ;; Distribute colours across predecessor ports
            (dolist (port (ports node))
              (when (typep port 'in-port)
                (dolist (connection (connections port))
                  (let ((other (if (eql port (left connection))
                                   (right connection)
                                   (left connection))))
                    (unless (color other)
                      (let ((color (position :available colors)))
                        (setf (color other) color)
                        (setf (aref colors color) :unavailable)))))))
            ;; Distribute colours across internal ports
            (dolist (port (ports node))
              (unless (typep port 'in-port)
                (let ((color (position :available colors)))
                  (setf (color port) color)
                  (setf (aref colors color) :unavailable))))
            (mark-adjacent node :available)))))))
