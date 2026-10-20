allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    if (project.name != "app") {
        afterEvaluate {
            val android = extensions.findByName("android")
            if (android != null) {
                try {
                    android.javaClass.getMethod("setCompileSdk", java.lang.Integer::class.java).invoke(android, 36)
                } catch (_: Exception) {
                    try {
                        android.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType).invoke(android, 36)
                    } catch (_: Exception) {}
                }
            }

            tasks.matching { it.name.contains("AarMetadata") && project.name == "file_picker" }.configureEach {
                enabled = false
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
