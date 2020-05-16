#!/bin/bash

USAGE="Usage: $0 [<release> ...]
"

[[ $# -gt 0 ]] || { echo "${USAGE}Expected at least one argument." >&2 ; exit 1 ; }

set -o pipefail
set -o errexit
set -o nounset

cat <<EOF
# THIS FILE IS GENERATED
#
# See: <https://github.com/jenkinsci/backend-update-center2/blob/master/site/generate-htaccess.sh>
RewriteEngine on

EOF

echo "# Version-specific rulesets generated by generate.sh"
n=$#
versions=( "$@" )
newestStable=
oldestStable=
oldestWeekly=

for (( i = n-1 ; i >= 0 ; i-- )) ; do
  version="${versions[i]}"
  IFS=. read -ra versionPieces <<< "$version"

  major=${versionPieces[0]}
  minor=${versionPieces[1]}
  patch=
  if [[ ${#versionPieces[@]} -gt 2 ]] ; then
    patch=${versionPieces[2]}
  fi

  if [[ "$version" =~ ^2[.][0-9]+[.][0-9]$ ]] ; then
    # This is an LTS version
    if [[ -z "$newestStable" ]] ; then
      newestStable="$version"
    fi

    cat <<EOF

# If major > ${major} or major = ${major} and minor >= ${minor} or major = ${major} and minor = ${minor} and patch >= ${patch}, use this LTS update site
RewriteCond %{QUERY_STRING} ^.*version=(\d)\.(\d+)\.(\d+)$ [NC]
RewriteCond %1 >${major}
RewriteRule ^(update\-center.*\.(json|html)+) /stable-${major}\.${minor}\.${patch}%{REQUEST_URI}? [NC,L,R=301]
RewriteCond %{QUERY_STRING} ^.*version=(\d)\.(\d+)\.(\d+)$ [NC]
RewriteCond %1 =${major}
RewriteCond %2 >=${minor}
RewriteRule ^(update\-center.*\.(json|html)+) /stable-${major}\.${minor}\.${patch}%{REQUEST_URI}? [NC,L,R=301]
RewriteCond %{QUERY_STRING} ^.*version=(\d)\.(\d+)\.(\d+)$ [NC]
RewriteCond %1 =${major}
RewriteCond %2 =${minor}
RewriteCond %3 >=${minor}
RewriteRule ^(update\-center.*\.(json|html)+) /stable-${major}\.${minor}\.${patch}%{REQUEST_URI}? [NC,L,R=301]
EOF
    oldestStable="$version"
  else
    # This is a weekly version
    # Split our version up into an array for rewriting
    # 1.651 becomes (1 651)
    oldestWeekly="$version"
    cat <<EOF

# If major > ${major} or major = ${major} and minor >= ${minor}, use this weekly update site
RewriteCond %{QUERY_STRING} ^.*version=(\d)\.(\d+)$ [NC]
RewriteCond %1 >${major}
RewriteRule ^(update\-center.*\.(json|html)+) /${major}\.${minor}%{REQUEST_URI}? [NC,L,R=301]
RewriteCond %{QUERY_STRING} ^.*version=(\d)\.(\d+)$ [NC]
RewriteCond %1 =${major}
RewriteCond %2 >${minor}
RewriteRule ^(update\-center.*\.(json|html)+) /${major}\.${minor}%{REQUEST_URI}? [NC,L,R=301]
EOF

  fi
done

cat <<EOF


# First LTS update site (stable-$oldestStable) gets all older LTS releases

RewriteCond %{QUERY_STRING} ^.*version=\d\.(\d+)\.\d+$ [NC]
RewriteRule ^(update\-center.*\.(json|html)+) /stable-${oldestStable}%{REQUEST_URI}? [NC,L,R=301]

RewriteCond %{QUERY_STRING} ^.*version=\d\.(\d+)+$ [NC]
RewriteRule ^(update\-center.*\.(json|html)+) /${oldestWeekly}%{REQUEST_URI}? [NC,L,R=301]

EOF


echo "# Add a RewriteRule for /stable which will always rewrite to the last LTS site we have"
cat <<EOF
RewriteRule ^stable/(.+) "/stable-${newestStable}/\$1" [NC,L,R=301]

EOF



# Further static rules
cat <<EOF


# These are static rules

# If that all failed, but we have an update center, let's go to current
RewriteRule ^(update\-center.*\.(json|html)+|latestCore\.txt) /current%{REQUEST_URI}? [NC,L,R=301]

# Ensure /release-history.json goes to the right place
RewriteRule ^release\-history\.json+ /current%{REQUEST_URI}? [NC,L,R=301]

# Ensure /plugin-documentation-urls.json goes to the right place
RewriteRule ^plugin\-documentation\-urls\.json+ /current%{REQUEST_URI}? [NC,L,R=301]

# Ensure /plugin-versions.json goes to the right place
RewriteRule ^plugin\-versions\.json+ /current%{REQUEST_URI}? [NC,L,R=301]


ReadmeName readme.html
IndexIgnore readme.html

# TODO: properly handle HTTPS in redirector

# For other tool installations under updates/
# HTTPS clients need to be served from HTTPS servers to avoid the error, so only send traffic to mirror for regular HTTP traffic
RewriteCond %{HTTPS} !=on
RewriteRule (.*\.json(\.html)?)$ http://mirrors.jenkins-ci.org/updates/\$1


# TODO this might be unnecessary?
# download/* directories contain virtual URL spaces for redirecting download traffic to mirrors.
RedirectMatch 302 /download/war/([0-9]*\.[0-9]*\.[0-9]*/jenkins)\.war$ http://mirrors.jenkins-ci.org/war-stable/\$1.war
RedirectMatch 302 /download/war/(.*)\.war$ http://mirrors.jenkins-ci.org/war/\$1.war
RedirectMatch 302 /download/plugins/(.*)\.hpi$ http://mirrors.jenkins-ci.org/plugins/\$1.hpi
EOF