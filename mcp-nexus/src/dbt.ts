import { readFileSync, existsSync } from "fs";
import { join, dirname, resolve } from "path";
import { fileURLToPath } from "url";
import yaml from "js-yaml";
import type { DbtProject, DbtProfile, DbtTarget } from "./types.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

export interface DbtConfig {
  project: DbtProject;
  profile: DbtProfile;
  target: DbtTarget;
  projectDir: string;
  profilesDir: string;
}

/**
 * Find dbt_project.yml starting from the current working directory
 */
export function findDbtProject(startDir: string = process.cwd()): string | null {
  let currentDir = resolve(startDir);

  while (currentDir !== dirname(currentDir)) {
    const projectFile = join(currentDir, "dbt_project.yml");
    if (existsSync(projectFile)) {
      return currentDir;
    }
    currentDir = dirname(currentDir);
  }

  return null;
}

/**
 * Load dbt_project.yml
 */
export function loadDbtProject(projectDir: string): DbtProject {
  const projectFile = join(projectDir, "dbt_project.yml");
  if (!existsSync(projectFile)) {
    throw new Error(`dbt_project.yml not found in ${projectDir}`);
  }

  const content = readFileSync(projectFile, "utf-8");
  return yaml.load(content) as DbtProject;
}

/**
 * Get profiles directory from environment or default location
 */
export function getProfilesDir(): string {
  const envDir = process.env.DBT_PROFILES_DIR;
  if (envDir) {
    return resolve(envDir);
  }

  const homeDir = process.env.HOME || process.env.USERPROFILE;
  if (!homeDir) {
    throw new Error("Could not determine home directory. Set DBT_PROFILES_DIR environment variable.");
  }

  return join(homeDir, ".dbt");
}

/**
 * Load profiles.yml
 */
export function loadProfiles(profilesDir: string): { [key: string]: DbtProfile } {
  const profilesFile = join(profilesDir, "profiles.yml");
  if (!existsSync(profilesFile)) {
    throw new Error(`profiles.yml not found in ${profilesDir}`);
  }

  const content = readFileSync(profilesFile, "utf-8");
  return yaml.load(content) as { [key: string]: DbtProfile };
}

/**
 * Get target configuration from profile
 */
export function getTarget(
  profile: DbtProfile,
  targetName?: string
): DbtTarget {
  const target = targetName || profile.target || "default";
  
  if (!profile.outputs || !profile.outputs[target]) {
    throw new Error(
      `Target "${target}" not found in profile "${profile.name}". Available targets: ${Object.keys(profile.outputs || {}).join(", ")}`
    );
  }

  return profile.outputs[target];
}

/**
 * Load complete dbt configuration
 */
export function loadDbtConfig(projectDir?: string): DbtConfig {
  const resolvedProjectDir = projectDir
    ? resolve(projectDir)
    : findDbtProject();

  if (!resolvedProjectDir) {
    throw new Error(
      "Could not find dbt_project.yml. Please run from a dbt project directory or specify --project-dir"
    );
  }

  const project = loadDbtProject(resolvedProjectDir);
  const profilesDir = getProfilesDir();
  const profiles = loadProfiles(profilesDir);

  const profileName = project.profile || project.name;
  const profile = profiles[profileName];

  if (!profile) {
    throw new Error(
      `Profile "${profileName}" not found in profiles.yml. Available profiles: ${Object.keys(profiles).join(", ")}`
    );
  }

  const target = getTarget(profile, project.target);

  return {
    project,
    profile,
    target,
    projectDir: resolvedProjectDir,
    profilesDir,
  };
}

