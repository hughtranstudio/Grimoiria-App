package app.grimoiria.core

import java.io.File

object TestSupport {
    val repoRoot: File = File(System.getProperty("grimoire.repoRoot") ?: "../..")
    val library: DefinitionLibrary by lazy {
        DefinitionLibrary.load(FolderDefinitionSource(File(repoRoot, "Sources/GrimoireCore/Resources/Definitions")))
    }
    val parser by lazy { ReadingParser(library) }
    fun fixture(path: String) = File(repoRoot, "Tests/GrimoireCoreTests/Fixtures/$path")
    fun tempDir(): File = kotlin.io.path.createTempDirectory("grimoire-capture-test").toFile()
}
