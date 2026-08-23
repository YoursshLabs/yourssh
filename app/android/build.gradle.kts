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
// Force every Android subproject (app + pub plugin modules such as file_picker)
// to compile against API 36. Some transitive plugins
// (flutter_plugin_android_lifecycle) now require compileSdk >= 36, while the
// Flutter SDK still defaults plugin modules to 34. Registered BEFORE the
// evaluationDependsOn(":app") block below so the afterEvaluate hook is in place
// before any subproject (including :app) is forced to evaluate.
subprojects {
    afterEvaluate {
        val androidExt = project.extensions.findByName("android")
        if (androidExt is com.android.build.gradle.BaseExtension) {
            androidExt.compileSdkVersion(36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
