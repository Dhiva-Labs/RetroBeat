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

// Some older Flutter plugins bundle their own AGP 4.x buildscript block.
// When AGP 4.x evaluates the android {} DSL first it silently drops the
// namespace property, leaving AGP 8.x with nothing to read. Read the
// namespace from the plugin's own AndroidManifest.xml as a fallback so the
// build doesn't fail.
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
