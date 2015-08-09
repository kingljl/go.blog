(use spiffy lowdown sxml-transforms intarweb uri-common files medea srfi-69 vector-lib srfi-13)

(define project-path "/Users/genius/project/src/github.com/tiancaiamao/go.blog/")
(define content-path (string-append project-path "content"))
(define INDEX 
  (with-input-from-file (string-append content-path "/index.json")
    (lambda ()
      (read-json))))

(define CATEGORY
  (let ((ret (make-hash-table)))
    (vector-for-each
     (lambda (i x)
       (let ((found (assq 'Category x)))
	 (when found
	       (let ((str (cdr found)))
		 (when (not (string=? str ""))
		       (if (hash-table-exists? ret str)
			   (hash-table-set! ret str (cons x (hash-table-ref ret str)))
			   (hash-table-set! ret str (cons x '()))))))))
     INDEX)
    ret))

(define TAGS
  (let ((ret (make-hash-table)))
    (vector-for-each 
     (lambda (_ x)
       (let ((found (assq 'Tags x)))
	 (when (and found
		    (not (null? (cdr found)))
		    (vector? (cdr found)))
	       (vector-for-each
		(lambda (_ str)
		  (when (not (string=? str ""))
			(if (hash-table-exists? ret str)
			    (hash-table-set! ret str (cons x (hash-table-ref ret str)))
			    (hash-table-set! ret str (cons x ret)))))
		(cdr found)))))
     INDEX)
    ret))

(include "template/root.scm")

(define (send-sxml sxml)
  (let ((body (with-output-to-string 
		(lambda () 
		  (SXML->HTML sxml)))))
    (send-response body: body)))

(define (md-handler filename)
  (send-sxml (page "title" 
		   (container
		    (with-input-from-file (string-append content-path "/" filename)
		      (lambda ()
			;; TODO check in INDEX
			(receive (content _) (markdown->sxml (current-input-port))
				 (article "title" "2014-01-23" content '() #f #f))))))))

(define (blog-handler)
  (send-sxml (page "blog" 
		   (container (blog (vector->list INDEX))))))

(define (about-handler)
  (send-sxml (page "About" (container (about)))))

(define router
  (lambda (continue)
    (let* ((req (current-request))
	   (uri (request-uri req))
	   (path (uri-path uri))
	   (pl (cdr path)))
      (if (null? (cdr pl))
	  (let ((p (car pl)))
	    (cond
	     ((string=? p "") 1)
	     ((string=? p "index") (blog-handler))
	     ((string=? p "about") (about-handler))
	     ((string=? p "category") 4)
	     ((string=? p "tags") 5)
	     ((string=? p "feed.atom") 6)
	     ((string-suffix-ci? ".md" p)
	      (parameterize ((file-extension-handlers 
			      `(("md" . ,md-handler)))
			     (root-path content-path))
			    (continue)))
	     (else
	      ((handle-not-found) path))))
	  (parameterize ((root-path "/Users/genius/project/src/github.com/tiancaiamao/go.blog/"))
			(continue))))))

(server-port 8088)

(vhost-map `((".*" . ,router)))