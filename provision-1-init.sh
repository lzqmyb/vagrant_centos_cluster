#! /bin/bash

mkdir -p /data/softs/localyum
cp -R /home/vagrant/softs/* /data/softs/localyum
yum install -y createrepo

