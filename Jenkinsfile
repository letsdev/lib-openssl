@Library('ld-shared')
import de.letsdev.*

node('docker') {

    def dockerImage
    stage('Prepare') {
        deleteDir()
        checkout scm
        dockerImage = docker.build('openssl')
    }

    def options = """
    -v $WORKSPACE:/home/build/app 
    -v $HOME/.m2:/home/build/.m2 
    -v $HOME/.gitconfig:/home/build/.gitconfig
    -v $HOME/ld-config:/home/build/ld-config
    """
    def pom = readMavenPom file: 'pom.xml'
    def VERSION = pom.version

    parallel(
        failFast: true,
        android: {
            stage('android') {  
                dockerImage.inside(options) {
                    sh "./build-android.sh ${VERSION}"
                    sh 'mvn deploy -P android'
                }
            }
        },
        ios: {
            stage('ios') {
                node('ios') {
                    deleteDir()
                    checkout scm
                    sh 'chmod a+x ./*.sh'
                    sh "./build-ios.sh ${VERSION}"
                    sh 'mvn deploy -P ios'
                }
            }
        }
    )

    stage('tag') {
        de.letsdev.git.LdGit ldGit = new de.letsdev.git.LdGit()
        ldGit.pushTag(VERSION)
    }
}