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

// Compatibility fixes for old Flutter plugins, registered BEFORE
// evaluationDependsOn triggers :app's evaluation (which causes Flutter's plugin
// loader to include and evaluate the plugin subprojects).  If this block came
// after evaluationDependsOn the hooks would arrive too late.
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android")
            as? com.android.build.gradle.LibraryExtension
            ?: return@afterEvaluate

        // 1. Namespace fallback
        // Plugins that bundle their own AGP 4.x buildscript block have the
        // android {} DSL evaluated by the old AGP first, which silently drops the
        // namespace property.  Read the manifest's package attribute as a fallback.
        if (android.namespace == null) {
            val manifest = file("src/main/AndroidManifest.xml")
            if (manifest.exists()) {
                Regex("""package\s*=\s*"([^"]+)"""")
                    .find(manifest.readText())
                    ?.groupValues
                    ?.getOrNull(1)
                    ?.let { android.namespace = it }
            }
        }

        // 2. JVM target alignment
        // The app targets JVM 17, and the Kotlin plugin propagates that as a
        // global default.  Old plugins that declare Java 1.8 keep their Java
        // target at 1.8 while Kotlin silently inherits 17, which AGP 8.x
        // rejects.  Align both to 17 so they are consistent.
        android.compileOptions.apply {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
            .configureEach { kotlinOptions { jvmTarget = "17" } }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
