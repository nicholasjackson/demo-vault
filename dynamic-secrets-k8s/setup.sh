#!/bin/bash -e
echo "##################################################"
echo "Install shipyard if you do not have it installed"
echo "curl https://shipyard.demo.gs/install.sh | bash"
echo "##################################################"

yard up --enable-consul false