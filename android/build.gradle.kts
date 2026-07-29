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

// Register the namespace fallback BEFORE evaluationDependsOn triggers :app's
// evaluation, which causes Flutter's plugin loader to include and evaluate the
// plugin subprojects. If this block came after evaluationDependsOn the hooks
// would arrive too late ("project already evaluated" error).
//
// Some older Flutter plugins bundle their own AGP 4.x buildscript block. The
// old AGP evaluates the android {} DSL first and silently discards the namespace
// property, leaving AGP 8.x with nothing. Reading the manifest's package
// attribute here provides a fallback so the build doesn't fail.
subprojects {
    afterEvaluate {
        extensions.findByName("android")
            ?.let { it as? com.android.build.gradle.LibraryExtension }
            ?.takeIf { it.namespace == null }
            ?.let { android ->
                val manifest = file("src/main/AndroidManifest.xml")
                if (manifest.exists()) {
                    Regex("""package\s*=\s*"([^"]+)"""")
                        .find(manifest.readText())
                        ?.groupValues
                        ?.getOrNull(1)
                        ?.let { android.namespace = it }
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
