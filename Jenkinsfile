@Library('ld-shared')
import de.letsdev.*

node('docker') {

    def dockerImage
    stage('Prepare') {
        deleteDir()
        checkout scm
        dockerImage = docker.build('openssl')
    }

    GString options = """
    -v ${env.WORKSPACE}:/home/build/app
    -v ${env.HOME}/.m2:/home/build/.m2
    -v ${env.HOME}/.gitconfig:/home/build/.gitconfig
    -v ${env.HOME}/ld-config:/home/build/ld-config
    """
    def pom = readMavenPom file: 'pom.xml'
    def VERSION = pom.version

    parallel(
            failFast: true,
            mac: {
                stage('Mac') {
                    node('ios') {
                        deleteDir()
                        checkout scm
                        sh "sudo xcode-select -s /Applications/Xcode-15.app"
                        sh "./build-mac.sh ${VERSION}"
                        sh 'mvn deploy -P mac'
                    }
                }
            },
            android: {
                stage('Android') {
                    dockerImage.inside(options) {
                        sh "./build-android.sh ${VERSION}"
                        sh 'mvn deploy -P android'
                    }
                }
            },
            ios: {
                stage('iOS') {
                    node('ios') {
                        deleteDir()
                        checkout scm
                        sh "sudo xcode-select -s /Applications/Xcode-15.app"
                        sh "./build-ios.sh ${VERSION}"
                        sh 'mvn deploy -P ios'
                    }
                }
            }
    )

    stage('tag') {
        tagPush(VERSION)
    }
}
