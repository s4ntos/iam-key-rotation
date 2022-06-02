# iam key rotation

Scripts to rotate the iam access and secret keys

Check https://github.com/jakebenn/aws-key-rotation-scripts repo for iam and ssh key rotation

##user_aws.sh
Rotates the iam key for an yaml configuration file.
Given a file with a structure like 

``
    Access_key : "1234567890ABCDEFG"
    Secret_key : "ABCDEFGHabcdeh123456/abcdefhABCDEH"
``

it will connect rotate the key and replace the file with the new key all using bash, particular usefull when aws-cli is not available for security reasons.

