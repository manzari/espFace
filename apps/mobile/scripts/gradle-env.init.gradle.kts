// Opt-in Gradle init script for restricted networks, mounted by scripts/flutter.sh (CI does not need it):
//  ESPFACE_MAVEN_MIRROR  Google Maven mirror added as a fallback repository to every build, including
//                        Flutter's included gradle plugin build (FAIL_ON_PROJECT_REPOS) and the app build.
//  ESPFACE_NDK_VERSION   NDK version forced on every Android module (plugins pin their own, e.g. jni),
//                        for an NDK that was mounted into the SDK instead of downloaded from dl.google.com.
//  ESPFACE_COMPILE_SDK   compileSdk forced on every Android module (plugins pin older platforms that are
//                        not installed in the image; compiling against the newer one is fine).
val mirror = System.getenv("ESPFACE_MAVEN_MIRROR") ?: ""
val ndk = System.getenv("ESPFACE_NDK_VERSION") ?: ""
val compileSdk = System.getenv("ESPFACE_COMPILE_SDK")?.toIntOrNull()

fun RepositoryHandler.addMirror() {
    if (mirror.isNotEmpty()) maven { url = uri(mirror) }
}

// plugins {} blocks in settings files resolve during evaluation, so plugin repositories must exist before it.
// Adding any repository drops the implicit gradlePluginPortal(), hence it is re-added explicitly.
beforeSettings {
    if (mirror.isNotEmpty()) {
        pluginManagement.repositories.addMirror()
        pluginManagement.repositories.gradlePluginPortal()
    }
}

settingsEvaluated {
    if (dependencyResolutionManagement.repositories.isNotEmpty()) {
        dependencyResolutionManagement.repositories.addMirror()
    } else {
        gradle.allprojects {
            buildscript.repositories.addMirror()
            repositories.addMirror()
        }
    }
}

// Registered at project creation, so it runs before AGP's own afterEvaluate creates the native tasks.
gradle.allprojects {
    afterEvaluate {
        val ext = extensions.findByName("android") ?: return@afterEvaluate
        fun call(name: String, arg: Any) =
            ext.javaClass.methods.firstOrNull { it.name == name && it.parameterCount == 1 }?.invoke(ext, arg)
        if (ndk.isNotEmpty()) call("setNdkVersion", ndk)
        if (compileSdk != null) call("setCompileSdk", compileSdk)
    }
}
