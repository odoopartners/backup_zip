@Library('jenkins-sharedlib') _

def deployments
List list_selected_sanitized

pipeline {
    agent {label 'master'}

    parameters {
        string(name: 'db_name', defaultValue: '', description: 'Name of the database you want to generate a backup')
    }

    stages {

        stage("Checkout") {
            steps {
                checkout scm
            }
        }

        stage("Obtaining list of deployments") {
            steps {
                script {

                    deployments = sh(
                        script: """docker run --rm \
                            -v ~/.aws:/root/.aws \
                            -v ~/.kube/config:/root/.kube/config \
                            odoopartners/awscli-kubectl:v1.0 \
                            kubectl get deployment -n odoo -o=name | grep odoo1 | sed "s/^.\\{16\\}//" """,
                        returnStdout: true
                    ).replaceAll('\n', ',')

                    List list_sanitized = deployments.split("\\s*,\\s*")
                    def final_list = list_sanitized.join(',')

                    env.DEPLOYMENTS = input message: 'Seleccione los deployments', ok: 'Continuar',
                        parameters: [extendedChoice(
                            name: 'Lista de deployments',
                            multiSelectDelimiter: ',',
                            type: 'PT_CHECKBOX',
                            value: "$final_list"
                        )]

                    printf "Lista de deployments seleccionados: \n${env.DEPLOYMENTS}"
                    list_selected_sanitized = env.DEPLOYMENTS.split("\\s*,\\s*")
                }
            }
        }

        stage("Generating backups") {
            steps {
                script {
                    generate_backup(list_selected_sanitized)
                }
            }
        }
    }

    post {
        always {
            deleteDir()
        }
    }
}


def generate_backup(list) {

    def pods
    List<String> list_pods

    for (int i = 0; i < list.size(); i++) {

        print("############# \n${list[i]} \n#############")

        pods = steps.sh(
            script: """docker run --rm \
                -v ~/.aws:/root/.aws \
                -v ~/.kube/config:/root/.kube/config \
                odoopartners/awscli-kubectl:v1.0 \
                kubectl get pods -n odoo -o=name --field-selector=status.phase=Running | grep ${list[i]} | sed "s/^.\\{4\\}//" """,
            returnStdout: true
        ).replaceAll('\n', ',')

        list_pods = Arrays.asList(pods.split("\\s*,\\s*"))

        if (list_pods[0].isEmpty()) {
            print("No hay pods disponibles")
        } else {
            for (int j = 0; j < list_pods.size(); j++) {
                print("* ${list_pods[j]}")

                print("Copying scripts ...")
                sh """docker run --rm \
                    -v ~/.aws:/root/.aws \
                    -v ~/.kube/config:/root/.kube/config \
                    -v ${env.WORKSPACE}:/workspace \
                    odoopartners/awscli-kubectl:v1.0 \
                    kubectl cp /workspace/gen_backup.py odoo/${list_pods[j]}:/tmp/gen_backup.py"""

                sh """docker run --rm \
                    -v ~/.aws:/root/.aws \
                    -v ~/.kube/config:/root/.kube/config \
                    -v ${env.WORKSPACE}:/workspace \
                    odoopartners/awscli-kubectl:v1.0 \
                    kubectl cp /workspace/odoo-backup.sh odoo/${list_pods[j]}:/tmp/odoo-backup.sh"""

                print("Executing scripts ...")
                sh """docker run --rm \
                    -v ~/.aws:/root/.aws \
                    -v ~/.kube/config:/root/.kube/config \
                    odoopartners/awscli-kubectl:v1.0 \
                    kubectl exec -n odoo ${list_pods[j]} -- bash --norc --noprofile -c \
                    'export LC_ALL=C; cd /tmp && python3 gen_backup.py localhost:8069 ${list[i]} ${db_name}'"""
            }
        }
    }
}
