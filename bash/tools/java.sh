# shellcheck shell=bash
# Maven shortcuts. Versions: jdkuse and mvnuse switch this machine's default.
#: mci | mvn clean install
#: mcis | mvn clean install, skipping tests
#: mvnq | quiet mvn
alias mci='mvn clean install'
alias mcis='mvn clean install -DskipTests'
alias mvnq='mvn -q'
