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
    project.evaluationDependsOn(":app")
}

subprojects {
    val updateCompileSdk = { p: Project ->
        val ext = p.extensions.findByName("android")
        if (ext != null) {
            for (m in ext.javaClass.methods) {
                if (m.name == "compileSdkVersion" || m.name == "setCompileSdkVersion" || m.name == "setCompileSdk") {
                    try { m.invoke(ext, 36) } catch (_: Throwable) {}
                }
            }
        }
    }
    if (project.state.executed) {
        updateCompileSdk(project)
    } else {
        project.afterEvaluate {
            updateCompileSdk(this)
        }
    }
}





tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
