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
        
    parallel(
        failFast: true,
        /*android: {
            stage('android') {  
                dockerImage.inside(options) {
                    sh build-android.sh
                    sh 'mvn deploy -Dclassifier=android'
                }
            }
        },*/
        ios: {
            stage('ios') {
                node('ios') {
                    deleteDir()
                    checkout scm
                    sh './build-ios.sh'
                    sh 'mvn deploy -Dclassifier=ios'
                }
            }
        }
    )

    stage('tag') {
        def pom = readMavenPom file: 'pom.xml'
        de.letsdev.git.LdGit ldGit = new de.letsdev.git.LdGit()
        ldGit.pushTag(pom.version)
    }
}