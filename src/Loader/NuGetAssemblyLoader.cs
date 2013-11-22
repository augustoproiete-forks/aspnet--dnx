﻿using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Versioning;
using Microsoft.CodeAnalysis;
using NuGet;

namespace Loader
{
    public class NuGetAssemblyLoader : IAssemblyLoader, IDependencyResolver, IAssemblyReferenceResolver
    {
        private readonly LocalPackageRepository _repository;
        private readonly Dictionary<string, Assembly> _cache = new Dictionary<string, Assembly>(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string, string> _paths = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        public NuGetAssemblyLoader(string packagesDirectory)
        {
            _repository = new LocalPackageRepository(packagesDirectory);
        }

        public Assembly Load(LoadOptions options)
        {
            string name = options.AssemblyName;

            Assembly assembly;
            if (_cache.TryGetValue(name, out assembly))
            {
                return assembly;
            }

            string path;
            if (_paths.TryGetValue(name, out path))
            {
                assembly = Assembly.LoadFile(path);

                _cache[name] = assembly;
            }

            return assembly;
        }

        public IEnumerable<Dependency> GetDependencies(string name, SemanticVersion version, FrameworkName frameworkName)
        {
            var package = FindCandidate(name, version);

            if (package != null)
            {
                return GetDependencies(package, frameworkName);
            }

            return null;
        }

        private IEnumerable<Dependency> GetDependencies(IPackage package, FrameworkName frameworkName)
        {
            IEnumerable<PackageDependencySet> dependencySet;
            if (VersionUtility.TryGetCompatibleItems(frameworkName, package.DependencySets, out dependencySet))
            {
                foreach (var set in dependencySet)
                {
                    foreach (var d in set.Dependencies)
                    {
                        var dependency = _repository.FindPackagesById(d.Id)
                                                    .Where(d.VersionSpec.ToDelegate())
                                                    .FirstOrDefault();
                        if (dependency != null)
                        {
                            yield return new Dependency
                            {
                                Name = dependency.Id,
                                Version = dependency.Version
                            };
                        }
                    }
                }
            }
        }

        public void Initialize(IEnumerable<Dependency> dependencies, FrameworkName frameworkName)
        {
            foreach (var dependency in dependencies)
            {
                var package = FindCandidate(dependency.Name, dependency.Version);

                if (package == null)
                {
                    continue;
                }

                foreach (var fileName in GetAssemblies(package, frameworkName))
                {
                    var an = AssemblyName.GetAssemblyName(fileName);

                    _paths[an.Name] = fileName;

                    if (!_paths.ContainsKey(package.Id))
                    {
                        _paths[package.Id] = fileName;
                    }
                }
            }
        }

        private IEnumerable<string> GetAssemblies(IPackage package, FrameworkName frameworkName)
        {
            var path = _repository.PathResolver.GetInstallPath(package);

            var directory = Path.Combine(path, "lib", VersionUtility.GetShortFrameworkName(frameworkName));

            if (!Directory.Exists(directory))
            {
                return GetAssembliesFromPackage(package, frameworkName, path);
            }

            return Directory.EnumerateFiles(directory, "*.dll");
        }

        public MetadataReference ResolveReference(string name)
        {
            string path;
            if (_paths.TryGetValue(name, out path))
            {
                return new MetadataFileReference(path);
            }

            return null;
        }

        private static IEnumerable<string> GetAssembliesFromPackage(IPackage package, FrameworkName frameworkName, string path)
        {
            IEnumerable<IPackageAssemblyReference> references;
            if (VersionUtility.TryGetCompatibleItems(frameworkName, package.AssemblyReferences, out references))
            {
                foreach (var reference in references)
                {
                    string fileName = Path.Combine(path, reference.Path);
                    yield return fileName;
                }
            }
        }

        private IPackage FindCandidate(string name, SemanticVersion version)
        {
            if (version == null)
            {
                return _repository.FindPackagesById(name).FirstOrDefault();
            }

            return _repository.FindPackage(name, version);
        }
    }
}