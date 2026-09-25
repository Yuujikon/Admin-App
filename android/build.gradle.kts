allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = if (project.projectDir.absolutePath.startsWith("C:", ignoreCase = true)) {
        // Fix for \"different roots\" error on Windows when building across drives.
        // If the project is on C: drive (like pub cache), keep its build dir on C:.
        project.layout.projectDirectory.dir("build")
    } else {
        newBuildDir.dir(project.name)
    }
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "org.jetbrains.kotlin") {
                useVersion("2.1.0")
            }
        }
    }
}

allprojects {
    tasks.matching { it.name.contains("UnitTest") }.configureEach {
        enabled = false
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
