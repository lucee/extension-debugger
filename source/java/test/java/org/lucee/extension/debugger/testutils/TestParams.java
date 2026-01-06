package org.lucee.extension.debugger.testutils;

import java.io.File;
import java.nio.file.Path;
import java.nio.file.Paths;

public class TestParams {
	public static class LuceeAndDockerInfo {
		// we'll probably eventually need to major/minor/patch info, but this is good enough for current needs
		public final int engineVersion;
		public final Path projectRoot = Paths.get("").toAbsolutePath();
		public final File dockerFile;

		LuceeAndDockerInfo(int engineVersion, String projectRelativeDockerRoot) {
			this.engineVersion = engineVersion;
			Path v = projectRoot.resolve(projectRelativeDockerRoot).normalize();
			this.dockerFile = v.resolve("Dockerfile").toFile();
		}

		public File getTestWebRoot(String webRoot) {
			File f = projectRoot.resolve("test/docker/" + webRoot).normalize().toFile();
			assert f.exists() : "No such file: '" + f + "'";
			return f;
		}

		@Override
		public String toString() {
			return "{engineVersion=" + engineVersion + ", dockerFile=" + dockerFile + "}";
		}
	}

	public static LuceeAndDockerInfo[] getLuceeAndDockerInfo() {
		return new LuceeAndDockerInfo[] {
			new LuceeAndDockerInfo(5, "test/docker/5"),
			new LuceeAndDockerInfo(6, "test/docker/6"),
			new LuceeAndDockerInfo(7, "test/docker/7")
		};
	}
}
