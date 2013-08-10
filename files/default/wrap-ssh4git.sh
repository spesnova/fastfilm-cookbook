#!/usr/bin/env bash
/usr/bin/env ssh -o "StrictHostKeyChecking=no" -i "/tmp/private_code/.ssh/deploy.id_rsa" $1 $2
