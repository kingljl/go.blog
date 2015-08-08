(define page
  (lambda (title content category tags)
    `(html (@ (lang "zh_CN"))
	   (head
	    (meta (@ (charset "utf-8")))
	    (meta (@ (name "description")
		     (content "")))
	    (title ,title)
	    (link (@ (rel "shortcut icon")
		     (href "/static/favicon.ico")))
	    (link (@ (rel "stylesheet")
		     (href "/static/bootstrap.min.css"))))
	   (body
	    (div (@ (class "navbar navbar-fixed-top navbar-inverse")
		    (role "navigation"))
		 (div (@ (class "container"))
		      (div (@ (class "collapse navbar-collapse"))
			   (ul (@ (class "nav navbar-nav"))
			       (li (a (@ href "/") "Home"))
			       (li (a (@ href "/index") "Blog"))
			       (li (a (@ href "http://github.com/tiancaiamao") "Project"))
			       (li (a (@ href "/about") "About"))
			       (li (a (@ href "/feed.atom") "Rss")))))
		 (div (@ (class "container"))
		      (div (@ (class "row row-offcanvas row-offcanvas-right"))
			   (div (@ (class "col-sm-9"))
				,@content)
			   (div (@ (class "col-sm-3"))
				(div (@ (class "well sidebar-nav"))
				     (ul (@ (class "nav"))
;;					 (li "Category")
;;					 ,(map (lambda (x)
;;						 `(li (a (@ (href "/category?name=" ,x)) ,x)))
;;					       category)
;;					 (li "Tags")
;;					 ,(map (lambda (x)
;;						 `(li (a (@ (href "/tags?name=" ,x)) ,x)))
;;					       tags))
					 ))))))))))

;; (SXML->HTML (page "test" '() '() '()))
