params: deploy: {
	// Number of NGINX instances to run
	replicas: int | *1

	// Clone static content from a git repo
	gitRepo: string | *""

	// Branch to clone 
	gitBranch: string | *""
}

containers: nginx: {
	image:  "nginx"
	scale:  params.deploy.replicas
	expose: "80:80/http"

	files: {
		"/etc/nginx/nginx.conf": "secret://nginx-conf/template"
	}

	dirs: {
		"/etc/nginx/conf.d": "secret://nginx-server-blocks"
	}

	if params.deploy.gitRepo != "" {
		sidecars: {
			git: {
				image: "alpine/git:v2.34.2"
				init:  true
				dirs: {
					"/var/www/html": "volume://site-data"
					"/acorn/ssh":    "secret://git-clone-ssh-keys"
				}
				files: {
					"/acorn/init.sh": "\(data.git.initScript)"
				}
				entrypoint: "/bin/sh /acorn/init.sh"
				command: [
					"clone",
					"\(params.deploy.gitRepo)",
					if params.deploy.gitBranch != "" {
						"-b \(params.deploy.gitBranch)"
					},
					"/var/www/html/",
				]
			}
		}

		dirs: {
			"/var/www/html": "volume://site-data"
		}
	}
}

if params.deploy.gitRepo != "" {
	volumes: {
		"site-data": {}
	}

}

secrets: {
	"nginx-conf": {
		type: "template"
		data: {
			template: """
				    user  nginx;
				    worker_processes  auto;

				    error_log  /var/log/nginx/error.log notice;
				    pid        /var/run/nginx.pid;

				    events {
				        worker_connections  1024;
				    }

				    http {
				        include       /etc/nginx/mime.types;
				        default_type  application/octet-stream;

				        log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
				                            '$status $body_bytes_sent "$http_referer" '
				                            '"$http_user_agent" "$http_x_forwarded_for"';

				        access_log  /var/log/nginx/access.log  main;

				        sendfile        on;
				        #tcp_nopush     on;

				        keepalive_timeout  65;

				        #gzip  on;

				        include /etc/nginx/conf.d/*.conf;
				    }
				"""
		}
	}
	"nginx-server-blocks": {
		type: "opaque"
		data: {
			"default.conf": """
				server {
					    listen       80;
					    listen  [::]:80;
					    server_name  localhost;

					    location / {
					        root   \(dataServerBlocks.htmlDir);
					        index  index.html index.htm;
					    }

					    # redirect server error pages to the static page /50x.html
					    #
					    error_page   500 502 503 504  /50x.html;
					    location = /50x.html {
					        root   \(dataServerBlocks.htmlDir);
					    }
				}
				"""
		}
	}
	"git-clone-ssh-keys": type: "opaque"
}

let dataServerBlocks = data.serverBlocks
data: {
	serverBlocks: {
		gitHtmlDir:    "/var/www/html"
		staticHtmlDir: "/usr/share/nginx/html"
		if params.deploy.gitRepo == "" {
			htmlDir: dataServerBlocks.staticHtmlDir
		}
		if params.deploy.gitRepo != "" {
			htmlDir: dataServerBlocks.gitHtmlDir
		}
	}
	git: {
		sshCommand: "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
		user:       "root"
		initScript: """
		#!/bin/sh
		set -x
		set -e
		ssh_dir="/\(data.git.user)/.ssh/"
		export GIT_SSH_COMMAND="\(data.git.sshCommand)"

		/bin/mkdir -p ${ssh_dir}
		/bin/chmod 700 ${ssh_dir}
		# sometimes the keys arent mounted
		sleep 3
		files=$(ls /acorn/ssh|wc -l)
		if [ "${files}" -gt "0" ]; then
			cp /acorn/ssh/* ${ssh_dir}
			chmod 600 ${ssh_dir}/*
		fi
		exec git "$@"
		"""
	}
}