.. role:: command(emphasis)
.. role:: field(code)
.. role:: file(emphasis)
.. role:: cmdflag(code)
.. role:: krmkind(emphasis)
.. role:: macro(code)
.. role:: pfield(code)
.. role:: rule(code)
.. role:: ruleattr(kbd)
.. role:: term(emphasis)
.. role:: tool(emphasis)
.. role:: type(emphasis)
.. role:: value(code)
.. |mandatory| replace:: **mandatory value**

=================================
:tool:`kustomize` rules for Bazel
=================================

.. External links
.. _sandboxing: https://docs.bazel.build/versions/master/sandboxing.html
.. _kustomization term: https://kubectl.docs.kubernetes.io/references/kustomize/glossary/#kustomization
.. See https://stackoverflow.com/a/4836544/31818 for this abomination:
.. |the kustomize tool| replace:: the :tool:`kustomize` tool
.. _the kustomize tool:
.. _kustomize: https://kubectl.docs.kubernetes.io/references/kustomize/glossary/#kustomize
.. _resources:
.. _resource: https://kubectl.docs.kubernetes.io/references/kustomize/glossary/#resource
.. _root: https://kubectl.docs.kubernetes.io/references/kustomize/glossary/#kustomization-root

Integrate |the kustomize tool|_ into your Bazel projects to build Kubernetes-style manifests.

.. contents:: :depth: 2

-----

Overview
========

These Bazel rules allow you to define `kustomizations <kustomization term_>`__ within your project workspace and capture the output of *building* those kustomizations with |the kustomize tool|_. Using :tool:`kustomize` within a Bazel project orchestrates both the preparation of the input files—for when static files won't do—and consumption of the resulting YAML document stream, situating :tool:`kustomize` as a transformer in the middle of that data flow.

:tool:`kustomize` operates on the Kubernetes Resource Model (KRM), and most often comes into play just ahead of Kubernetes API clients like :tool:`kubectl`, sending the YAML document stream to the Kubernetes API to apply the resources_ to the cluster. These rules do no include any such interaction with the Kubernetes API. Instead, they focus solely on emitting the resources defined by the :term:`kustomization`.

The rules download :tool:`kustomize` through a module extension, described under `Integrating Into Your Project`_. When a :term:`kustomization` inflates Helm charts, the rules supply the :tool:`helm` tool provided by the `rules_helm <https://github.com/periareon/rules_helm>`__ Bazel module.

Simple Example
--------------

Here we'll walk through a simple example to give a feel for how to use these Bazel rules.

Assume you have a :term:`kustomization` that defines a single Kubernetes :krmkind:`ConfigMap`, taking its data entries from both a file containing "environment variable"-style line-by-line definitions and some inline definitions in the :file:`kustomization.yaml` file. First, the :file:`kustomization.yaml` file:

.. code:: yaml

    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization

    configMapGenerator:
    - name: translations
      envs:
      - config-bindings
      literals:
      - HELLO=hola
      - GOODBYE=adios

Note that the "envs" field references a sibling file named :file:`config-bindings`, with content as follows:

.. code::

    THANK_YOU=gracias

If we run the :command:`kustomize build` command against the directory containing these two files, it emits the following YAML document:

.. code:: yaml

    apiVersion: v1
    data:
      GOODBYE: adios
      HELLO: hola
      THANK_YOU: gracias
    kind: ConfigMap
    metadata:
      name: translations-74424tmdd8

Now, let's teach Bazel to produce the same document.

By convention, we'll add a couple of Bazel targets to the :file:`BUILD.bazel` file in the same directory. First, we define the `kustomization <kustomization term_>`__ itself, indicating where the :term:`kustomization` file sits and which other files it depends on. For this, we use the kustomization_ rule.

.. code:: bazel

   load(
        "@rules_kustomize//kustomize:defs.bzl",
        "kustomization",
    )

    kustomization(
        name = "base",
        src = "kustomization.yaml",
        srcs = [
            "config-bindings",
        ],
    )

The kustomization_ rule's :ruleattr:`src` attribute names the :file:`kustomization` file. It's usually :file:`kustomization.yaml`, but you can also point it at other file names, such as the :file:`kustomization.yml` or :file:`kustomization` alternatives that the :tool:`kustomize` tool accepts.

This "base" target we've defined builds nothing. It prepares the recipe for building artifacts, in the same way that a :term:`kustomization`'s files are inert input for the :tool:`kustomize` tool. The target does stand for its :file:`kustomization.yaml` file, with everything the :term:`kustomization` references as its runfiles, so a test or tool that reads the sources can list it in :ruleattr:`data` and find the file through :cmdflag:`$(rlocationpath)`. When we'd like to build the :term:`kustomization` using particular options—as we would by invoking :command:`kustomize build`—we define another target in a :file:`BUILD.bazel` file. Here we'll add to the same Bazel package, this time using the kustomized_resources_ rule.

.. code:: bazel

    load(
        "@rules_kustomize//kustomize:defs.bzl",
        "kustomized_resources",
    )

    kustomized_resources(
        name = "simple",
        kustomization = ":base",
    )

When we tell Bazel to build this new "simple" target, it will invoke :command:`kustomize build` and write the output to a file named :file:`simple.yaml`. That's the default mapping from target name to output file name, but you can change it with the kustomized_resources_ rule's :ruleattr:`result` attribute. Other Bazel targets can then demand this file as input, forcing Bazel to rebuild the file whenever—and only when—any of the input files change.

The `examples <examples>`__ directory holds two modules exercising the rules. `examples/simple <examples/simple>`__ has a plain :term:`kustomization` and one whose rendered manifests are written back into the source tree with :command:`bazel run`. `examples/helm <examples/helm>`__ patches manifests rendered by `rules_helm <https://github.com/periareon/rules_helm>`__.

Integrating Into Your Project
=============================

In order to use these rules in your Bazel project, you must instruct Bazel to download the source and run the functions that make the rules available. Add the following to your project's :file:`MODULE.bazel` file.

.. code:: bazel

    bazel_dep(name = "rules_kustomize", version = "0.6.0")

That declaration alone registers :tool:`kustomize` toolchains for the default version, as :file:`rules_kustomize` evaluates its own :field:`kustomize` module extension and registers the resulting hub. The :tool:`helm` tool, used only by :term:`kustomizations` that inflate Helm charts, comes from the `rules_helm <https://github.com/periareon/rules_helm>`__ Bazel module, which likewise registers its toolchains automatically.

To choose a different version, declare the hub yourself with the extension's :field:`toolchain` tag. It creates a repository (named :value:`kustomize_toolchains` by default) holding a toolchain for every platform :tool:`kustomize` is released on, and registering :value:`@kustomize_toolchains//:all` lets Bazel pick the one matching each execution platform:

.. code:: bazel

    kustomize = use_extension("@rules_kustomize//kustomize:extensions.bzl", "kustomize")
    kustomize.toolchain(version = "5.7.1")
    use_repo(kustomize, "kustomize_toolchains")

    register_toolchains("@kustomize_toolchains//:all")

To run the same :tool:`kustomize` binary yourself, add the :field:`host_tools` tag. It creates a repository (named :value:`kustomize` by default) exposing, as :value:`@kustomize//:kustomize`, the binary a hub (:value:`kustomize_toolchains` unless its :field:`toolchains` attribute says otherwise) holds for the host platform. That target runs :tool:`kustomize` from the directory in which you invoked :command:`bazel run`, so relative paths such as :command:`bazel run @kustomize -- build ./overlay` resolve as they would with a locally installed :tool:`kustomize`. Several versions can live side by side by pairing each hub with a host repository of its own.

.. code:: bazel

    kustomize.host_tools()
    use_repo(kustomize, "kustomize")

Rules of your own can consume the toolchain through :value:`@rules_kustomize//kustomize:toolchain_type`, whose :type:`ToolchainInfo` carries the :pfield:`kustomize` binary and its :pfield:`version`. The :value:`@rules_kustomize//kustomize:current_toolchain` target exposes the resolved binary to :type:`genrule` and friends as the :value:`KUSTOMIZE` (execpath) and :value:`KUSTOMIZE_RLOCATIONPATH` (rlocationpath) make variables.

With those calls in place, you're now ready to use the rules in your Bazel packages.

Tool Versions
=============

:file:`rules_kustomize` records SHA-256 checksums for a single :tool:`kustomize` version—the default. Requesting any other version makes the extension download that release's :file:`checksums.txt` file while it is evaluated. On Bazel 8.5 and newer, the digests are then stored as facts in your :file:`MODULE.bazel.lock` file, so the lookup happens once per version and air-gapped builds keep working from the lockfile. Older Bazel versions repeat the lookup whenever the extension is re-evaluated.

:tool:`helm` versions are whichever the :file:`rules_helm` module considers current. To pin a particular :tool:`helm` version, set the :cmdflag:`--@rules_helm//helm/settings:version` flag, such as in your project's :file:`.bazelrc` file:

.. code::

    build --@rules_helm//helm/settings:version=3.19.0

See each of those projects' documentation for the set of versions they know how to download.

Running the Tool Yourself
==================
If you'd like to run the same :tool:`kustomize` tool that these rules use, you can have Bazel run it for you, without installing the tool separately. The :field:`host_tools` tag described in `Integrating Into Your Project`_ creates the :value:`@kustomize` repository for that purpose.

.. code:: shell

    bazel run @kustomize -- version

Bazel downloads the tool the first time that you ask for it. You get the same version that your builds use: the one held by the hub the tag names, or the default version otherwise.

That label always names the binary for the machine running Bazel, so don't lean on it in build actions. A :rule:`genrule` target can instead list :value:`@rules_kustomize//kustomize:current_toolchain` in its :ruleattr:`toolchains` attribute and refer to the :value:`$(KUSTOMIZE)` make variable. Bazel then supplies the tool built for whichever machine will run that action, which may not be the computer in front of you when you use remote execution.
=======
Remote Content
==============

:tool:`kustomize` can fetch content for itself while building: it clones repositories named as remote resources_ and runs :command:`helm pull` for charts it doesn't find below :field:`chartHome`. Bazel actions have no network access, so that content has to be fetched while Bazel resolves repositories instead, with a verified checksum, and then placed where the :term:`kustomization` expects it. The kustomization_ rule has an attribute for each case; the fetching itself is left to repository rules that already exist.

.. _remote bases:

For a remote base, fetch its source archive with :type:`http_archive` (or :type:`git_repository`) from :file:`@bazel_tools` and declare it as a kustomization_ in the repository's BUILD file, with an :ruleattr:`include_prefix` naming the directory below a depending :term:`kustomization`'s root at which it is placed. Each consumer then lists it in :ruleattr:`deps` and refers to that directory in place of the URL, the way a :type:`cc_library`'s :ruleattr:`include_prefix` fixes the path by which its headers are included. Here the :file:`examples/helloWorld` directory of the :tool:`kustomize` repository serves as a base:

.. code:: bazel

    http_archive = use_repo_rule("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

    http_archive(
        name = "hello_world",
        build_file_content = """
    load("@rules_kustomize//kustomize:defs.bzl", "kustomization")

    kustomization(
        name = "helloWorld",
        src = "kustomization.yaml",
        include_prefix = "bases/helloWorld",
        srcs = glob(["**"], exclude = ["BUILD.bazel", "kustomization.yaml"]),
        visibility = ["//visibility:public"],
    )
    """,
        sha256 = "4ea5a974c46ad6efcde4fd9c339ab1bd278a80b6872dda2d1a366936e4638475",
        strip_prefix = "kustomize-kustomize-v5.8.1/examples/helloWorld",
        urls = ["https://github.com/kubernetes-sigs/kustomize/archive/refs/tags/kustomize/v5.8.1.tar.gz"],
    )

.. code:: bazel

    kustomization(
        name = "overlay",
        src = "kustomization.yaml",
        deps = ["@hello_world//:helloWorld"],
    )

.. code:: yaml

    resources:
    - bases/helloWorld

.. _remote charts:

For a Helm chart, fetch the packaged chart with :type:`helm_import_repository` from `rules_helm <https://github.com/periareon/rules_helm>`__, which locates it in a chart repository's :file:`index.yaml`, at a direct URL, or in an OCI registry. Its :type:`helm_import` target provides the chart archive, which the :ruleattr:`helm_charts` attribute unpacks below the :term:`kustomization`'s :ruleattr:`chart_home` before building, so the :field:`helmCharts` field finds the chart under its name and skips the download:

.. code:: bazel

    helm_import_repository = use_repo_rule("@rules_helm//helm:defs.bzl", "helm_import_repository")

    helm_import_repository(
        name = "minecraft_chart",
        chart_name = "minecraft",
        repository = "https://itzg.github.io/minecraft-server-charts",
        sha256 = "4cd47bbc4f9a41ea3915b996ea85cec49efe6671a1cf5a7bef8ee159d6a76c09",
        version = "3.1.4",
    )

.. code:: bazel

    kustomization(
        name = "server",
        src = "kustomization.yaml",
        helm_charts = ["@minecraft_chart//:minecraft"],
    )

.. code:: yaml

    helmCharts:
    - name: minecraft
      version: 3.1.4
      releaseName: test

A chart packaged by :file:`rules_helm`'s :type:`helm_chart` rule in the same workspace works the same way; see `examples/helm <examples/helm>`__.

Rules
=====

kustomization
-------------

This defines a `kustomization <kustomization term_>`__ from a set of source files and other `kustomizations <kustomization_>`_, intended for referencing from one or more dependent kustomized_resources_ targets.

Providers
^^^^^^^^^

* KustomizationInfo_

Attributes
^^^^^^^^^^
+-----------------------------------------+-----------------------------+---------------------------------------+
| **Name**                                | **Type**                    | **Default value**                     |
+-----------------------------------------+-----------------------------+---------------------------------------+
| :ruleattr:`name`                        | :type:`string`              | |mandatory|                           |
+-----------------------------------------+-----------------------------+---------------------------------------+
| A unique name for the :term:`kustomization`. As there is usually only one such target defined  per Bazel      |
| package (assuming that the target is in the same package as the :term:`kustomization` file), a simple name    |
| like "base" is fitting.                                                                                       |
+-----------------------------------------+-----------------------------+---------------------------------------+
| :ruleattr:`chart_home`                  | :type:`string`              | :value:`charts`                       |
+-----------------------------------------+-----------------------------+---------------------------------------+
| The directory below the :term:`kustomization` root into which the :ruleattr:`helm_charts` are unpacked. Must  |
| agree with the :field:`helmGlobals.chartHome` field, whose default this matches.                              |
+-----------------------------------------+-----------------------------+---------------------------------------+
| :ruleattr:`deps`                        | :type:`label_list`          | :value:`[]`                           |
+-----------------------------------------+-----------------------------+---------------------------------------+
| The set of `kustomizations <kustomization_>`_ referenced as resources_ by this :term:`kustomization`.         |
+-----------------------------------------+-----------------------------+---------------------------------------+
| :ruleattr:`src`                         | :type:`label`               | |mandatory|                           |
+-----------------------------------------+-----------------------------+---------------------------------------+
| :file:`kustomization.yaml`, :file:`kustomization.yml`, or :file:`kustomization` file for this                 |
| :term:`kustomization`.                                                                                        |
+-----------------------------------------+-----------------------------+---------------------------------------+
| :ruleattr:`helm_charts`                 | :type:`label_list`          | :value:`[]`                           |
+-----------------------------------------+-----------------------------+---------------------------------------+
| Packaged Helm charts (:file:`.tgz` archives) for the :field:`helmCharts` field to inflate. Each archive is     |
| unpacked below :ruleattr:`chart_home` before building, where :tool:`kustomize` finds the chart by name and     |
| doesn't attempt to download it. Archives may come from `rules_helm <https://github.com/periareon/rules_helm>`__,|
| whether a chart it packages or one its :type:`helm_import_repository` fetches (see `remote charts`_).          |
+-----------------------------------------+-----------------------------+---------------------------------------+
| :ruleattr:`include_prefix`              | :type:`string`              | :value:`""`                           |
+-----------------------------------------+-----------------------------+---------------------------------------+
| The directory below a depending :term:`kustomization`'s root at which this :term:`kustomization` is placed.   |
| A :term:`kustomization` in another repository can't be reached by a relative path from the ones that use it,  |
| so it declares one: with :value:`bases/helloWorld`, every :term:`kustomization` listing it in :ruleattr:`deps` |
| finds it at :file:`bases/helloWorld`, its own bases alongside (see `remote bases`_). Left empty, the           |
| :term:`kustomization` keeps its own location, which is what bases within the same repository want.            |
+-----------------------------------------+-----------------------------+---------------------------------------+
| :ruleattr:`srcs`                        | :type:`label_list`          | :value:`[]`                           |
+-----------------------------------------+-----------------------------+---------------------------------------+
| Files referenced as resources_ for this :term:`kustomization`.                                                |
+-----------------------------------------+-----------------------------+---------------------------------------+

Example
^^^^^^^

.. code:: bazel

    kustomization(
        name = "overlay",
        deps = [
            # This target "base:base" is another kustomization.
            "//apps/base"
        ],
        src = "kustomization.yaml",
        srcs = [
            # This target "charts:charts" is a filegroup.
            "//apps/base/charts",
            "extras.yaml",
        ],
    )

kustomized_resources
--------------------

This defines an invocation of the :command:`kustomize build` command against a :term:`kustomization` `target <https://kubectl.docs.kubernetes.io/references/kustomize/glossary/#target>`_, creating a resulting set of :term:`resources` (collectively, a `variant <https://kubectl.docs.kubernetes.io/references/kustomize/glossary/#variant>`_).

Before invoking :tool:`kustomize`, the rule copies the :term:`kustomization`'s files—whether they come from the source tree or were generated by other Bazel rules—into a private directory tree laid out like Bazel's runfiles tree, so that :tool:`kustomize` finds them side by side in the relative locations the :term:`kustomization` expects.

It then reads the :term:`kustomization` files in that tree, bases and components included, to turn on the :tool:`kustomize` features they call for. A :field:`helmCharts` or :field:`helmGlobals` field enables the Helm chart inflator (the :cmdflag:`--enable-helm` and :cmdflag:`--helm-command` flags, pointing at the :tool:`helm` toolchain); a :field:`generators`, :field:`transformers` or :field:`validators` field enables plugins and exec functions (the :cmdflag:`--enable-alpha-plugins` and :cmdflag:`--enable-exec` flags). Nothing needs declaring on the Bazel side.

See the Difficulties_ section below for considerations with :term:`kustomizations` that involve use of the :field:`helmCharts` :krmkind:`Kustomization` (or :krmkind:`Component`) field.

Attributes
^^^^^^^^^^

+---------------------------------------+-----------------------------+---------------------------------------+
| **Name**                              | **Type**                    | **Default value**                     |
+---------------------------------------+-----------------------------+---------------------------------------+
| :ruleattr:`name`                      | :type:`string`              | |mandatory|                           |
+---------------------------------------+-----------------------------+---------------------------------------+
| A unique name for the :term:`variant`.                                                                      |
+---------------------------------------+-----------------------------+---------------------------------------+
| :ruleattr:`env`                       | :type:`string_dict`         | :value:`{}`                           |
+---------------------------------------+-----------------------------+---------------------------------------+
| Environment variables for the build, on top of Bazel's action environment (:cmdflag:`--action_env`).         |
| :tool:`kustomize` passes its environment on to the exec functions and plugins it runs, so this is how they   |
| are configured.                                                                                             |
+---------------------------------------+-----------------------------+---------------------------------------+
| :ruleattr:`kustomization`             | :type:`label`               | |mandatory|                           |
+---------------------------------------+-----------------------------+---------------------------------------+
| The :term:`kustomization` to build.                                                                         |
|                                                                                                             |
| This may refer to a target using the kustomization_ rule or another rule that yields a KustomizationInfo_   |
| provider.                                                                                                   |
+---------------------------------------+-----------------------------+---------------------------------------+
| :ruleattr:`result`                    | :type:`output`              | :value:`<name>.yaml`                  |
+---------------------------------------+-----------------------------+---------------------------------------+
| The built result, as a YAML stream of KRM resources in separate documents (per the :cmdflag:`--output`      |
| :tool:`kustomize` flag).                                                                                    |
+---------------------------------------+-----------------------------+---------------------------------------+

Example
^^^^^^^

.. code:: bazel

    kustomized_resources(
        name = "production",
        env = {
            "CLUSTER_NAME": "prod1234",
            "ENVIRONMENT": "production",
        },
        kustomization = ":overlay",
    )

Providers
=========

KustomizationInfo
-----------------

:type:`KustomizationInfo` summarizes a :term:`kustomization` root_, as provided by the kustomization_ rule.

Fields
^^^^^^

+---------------------------------------+----------------------------------------------------------+
| **Name**                              | **Type**                                                 |
+---------------------------------------+----------------------------------------------------------+
| :pfield:`include_prefix`              | :type:`string`                                           |
+---------------------------------------+----------------------------------------------------------+
| The directory below a depending :term:`kustomization`'s root at which this one is placed, or     |
| empty to keep its own location.                                                                  |
+---------------------------------------+----------------------------------------------------------+
| :pfield:`target_file`                 | :type:`string`                                           |
+---------------------------------------+----------------------------------------------------------+
| The top-level :term:`kustomization` file defining this :term:`kustomization`.                    |
+---------------------------------------+----------------------------------------------------------+
| :pfield:`transitive_layout`           | :type:`depset of struct`                                 |
+---------------------------------------+----------------------------------------------------------+
| Where each referenced file sits when the :term:`kustomization` is built, as                      |
| :value:`struct(file, path, extract)` entries: the :type:`File`, its path relative to the staging |
| root, and whether it is an archive to unpack there rather than a file to copy.                   |
+---------------------------------------+----------------------------------------------------------+
| :pfield:`transitive_resources`        | :type:`depset of File`                                   |
+---------------------------------------+----------------------------------------------------------+
| The set of files (including other :term:`kustomizations`) referenced by this                     |
| :term:`kustomization`.                                                                           |
+---------------------------------------+----------------------------------------------------------+

Difficulties
============

These rules attempt to make using :tool:`kustomize` with Bazel easier, but there are a few features of the tools that interact poorly, or at least surprisingly, even when they're individually doing their job as intended. We can work around each problem once we know better what to expect.

Bazel's Sandbox and Load Restrictors
------------------------------------

:tool:`kustomize` prefers to load files only from the :term:`kustomization` root directory—the one containing the :file:`kustomization.yaml` file—or any of its subdirectories. The :command:`kustomize build` command runs with a :term:`load restrictor` to enforce this restrictive policy. By default, the :cmdflag:`--load-restrictor` flag uses the value :value:`LoadRestrictionsRootOnly`. With that value in effect, :tool:`kustomize` will refuse to read any files referenced by a :term:`kustomization` that lie outside of the :term:`kustomization` root directory tree, per `this FAQ entry <https://kubectl.docs.kubernetes.io/faq/kustomize/#security-file-foo-is-not-in-or-below-bar>`__.

Bazel can execute the actions for its :command:`build` and :command:`test` commands in a restricted environment called a :term:`sandbox`, using a technique called sandboxing_. On some operating systems, Bazel uses symbolic links to make only some files available to programs it runs in its actions. :tool:`kustomize` resolves such links before checking where a file lies, and considers links that point outward from the :term:`kustomization` root to transgress its :value:`LoadRestrictionsRootOnly` load restriction.

The kustomized_resources_ rule sidesteps this problem by copying—rather than linking—the :term:`kustomization`'s files into the private directory tree it hands to :tool:`kustomize`. The default load restrictor therefore behaves within Bazel as it does outside of it, and you only need to relax it, by passing :cmdflag:`--load-restrictor LoadRestrictionsNone` through the rule's :ruleattr:`args` attribute, when the :term:`kustomization` itself reaches outside of its root.

Downloading Helm Charts
-----------------------

The :tool:`kustomize` tool can expand Helm charts using the :krmkind:`Kustomization` manifest's :field:`helmCharts` `field <https://github.com/kubernetes-sigs/kustomize/blob/master/examples/chart.md>`__. If the Helm chart's source files are not available already locally, :tool:`kustomize` can fetch the chart archive and unpack within the directory specified in the :field:`helmGlobals.chartHome` `field <https://github.com/kubernetes-sigs/kustomize/blob/master/examples/chart.md#build-the-base-and-the-variants>`__. By default, this :field:`chartHome` field's value is :value:`charts`, meaning that :tool:`kustomize` will download and expand chart archives in the :file:`charts/<chart name>` directory within the :term:`kustomization` root.

Now, first, let's acknowledge that the :tool:`kustomize` maintainers do **not** recommend `downloading Helm charts automatically <https://github.com/kubernetes-sigs/kustomize/blob/master/examples/chart.md#but-its-not-really-about-performance>`__, nor `even relying on Helm for repeated expansion at all <https://github.com/kubernetes-sigs/kustomize/blob/master/examples/chart.md#best-practice>`__. Within Bazel, the download can't happen at all: a sandboxed action has no network access, and :tool:`kustomize` would need to write the chart into the :term:`kustomization` root.

Instead, fetch the chart ahead of time. Either commit the unpacked chart below :file:`charts/<chart name>` and list its files in the kustomization_ rule's :ruleattr:`srcs`, or let :file:`rules_helm`'s :type:`helm_import_repository` fetch the archive with a verified checksum and list it in :ruleattr:`helm_charts` (see `remote charts`_). Both place the chart where :tool:`kustomize` looks for it, so the :field:`helmCharts` entry's :field:`repo` field is left unused.

Also note that :tool:`kustomize` doesn't apply the :krmkind:`Kustomization` manifest's top-level :field:`namespace` field to the resources_ a :field:`helmCharts` entry produces. Set the entry's own :field:`namespace` field for charts that template :value:`.Release.Namespace`, or apply the namespace from an overlay that uses the chart's :term:`kustomization` as a base.
