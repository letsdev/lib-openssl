##########################################################################################
How to build.
1. Put openssl source in this folder named "openssl-<VERSION>"
3. change the version in the pom.xml file to the open ssl version you want to build.
4. the libs are contained in lib/android and lib/ios after build

##########################################################################################
For iOS !!!

The Wrapper needs Openssl.framework 
The iOS Projekt needs Ssl.framework and Crypto.framework

Why this is so is currently unkonwn to me. Fact is it doesn't really matter. The lib is not included twice since the wrapper only needs it to compile successful and does not inculde the lib itself.

##########################################################################################