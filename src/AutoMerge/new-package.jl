function pull_request_build(api::GitHub.GitHubAPI,
                            ::NewPackage,
                            pr::GitHub.PullRequest,
                            current_pr_head_commit_sha::String,
                            registry::GitHub.Repo;
                            auth::GitHub.Authorization,
                            authorized_authors::Vector{String},
                            authorized_authors_special_jll_exceptions::Vector{String},
                            registry_head::String,
                            registry_master::String,
                            suggest_onepointzero::Bool,
                            whoami::String,
                            registry_deps::Vector{<:AbstractString} = String[])::Nothing
    # first check if the PR is open, and the author is authorized - if not, then quit
    # if the PR is open and the author is authorized, then check rules 0 through 10.
    # Rules:
    # 0. A JLL-only author (e.g. `jlbuild`) is not allowed to register non-JLL packages.
    # 1. Only changes a subset of the following files:
    #     - `Registry.toml`,
    #     - `E/Example/Compat.toml`
    #     - `E/Example/Deps.toml`
    #     - `E/Example/Package.toml`
    #     - `E/Example/Versions.toml`
    # 2. TODO: implement this check. When implemented, this check will make sure that the changes to `Registry.toml` only modify the specified package.
    # 3. Normal capitalization
    #     - name should match r"^[A-Z]\w*[a-z]\w*[0-9]?$"
    #     - i.e. starts with a capital letter, ASCII alphanumerics only, contains at least 1 lowercase letter
    # 4. Not too short
    #     - at least five letters
    #     - you can register names shorter than this, but doing so requires someone to approve
    # 5. Meets julia name check
    #     - does not include the string "julia" with any case
    #     - does not start with "Ju"
    # 6. DISABLED. Standard initial version number - one of 0.0.1, 0.1.0, 1.0.0, X.0.0
    #     - does not apply to JLL packages
    # 7. DISABLED. Repo URL ends with /$name.jl.git where name is the package name. Now that we have support for multiple packages in different subdirectories of a repo, we have disabled this check.
    # 8. Compat for all dependencies
    #     - there should be a [compat] entry for Julia
    #     - all [deps] should also have [compat] entries
    #     - all [compat] entries should have upper bounds
    #     - dependencies that are standard libraries do not need [compat] entries
    #     - dependencies that are JLL packages do not need [compat] entries
    # 9. (only applies to JLL packages) The only dependencies of the package are:
    #     - Pkg
    #     - Libdl
    #     - other JLL packages
    # 10. Package's name is sufficiently far from existing package names in the registry
    #     - We exclude JLL packages from the "existing names"
    #     - We use three checks:
    #         - that the lowercased name is at least 1 away in Damerau Levenshtein distance from any other lowercased name
    #         - that the name is at least 2 away in Damerau Levenshtein distance from any other name
    #         - that the name is sufficiently far in a visual distance from any other name
    # 11. Package's name has only ASCII characters
    # 12. Version can be installed
    #     - given the proposed changes to the registry, can we resolve and install the new version of the package?
    #     - i.e. can we run `Pkg.add("Foo")`
    # 13. Version can be loaded
    #     - once it's been installed (and built?), can we load the code?
    #     - i.e. can we run `import Foo`
    pkg, version = parse_pull_request_title(NewPackage(), pr)
    this_is_jll_package = is_jll_name(pkg)
    @info("This is a new package pull request", pkg, version, this_is_jll_package)
    pr_author_login = author_login(pr)
    if is_open(pr)
        if pr_author_login in vcat(authorized_authors, authorized_authors_special_jll_exceptions)
            description = "New package. Pending."
            params = Dict("state" => "pending",
                          "context" => "automerge/decision",
                          "description" => description)
            my_retry(() -> GitHub.create_status(api,
                                                registry,
                                                current_pr_head_commit_sha;
                                                auth = auth,
                                                params = params))

            if this_is_jll_package
                if pr_author_login in authorized_authors_special_jll_exceptions
                    this_pr_can_use_special_jll_exceptions = true
                else
                    this_pr_can_use_special_jll_exceptions = false
                end
            else
                this_pr_can_use_special_jll_exceptions = false
            end

            if this_is_jll_package
                g0 = true
                m0 = ""
            else
                if pr_author_login in authorized_authors
                    g0 = true
                    m0 = ""
                else
                    g0 = false
                    m0 = "This package is not a JLL package. The author of this pull request is not authorized to register non-JLL packages."
                end
            end

            g1, m1 = pr_only_changes_allowed_files(api,
                                                   NewPackage(),
                                                   registry,
                                                   pr,
                                                   pkg;
                                                   auth = auth)
            g2 = true
            m2 = ""
            if this_pr_can_use_special_jll_exceptions
                g3 = true
                g4 = true
                m3 = ""
                m4 = ""
            else
                g3, m3 = meets_normal_capitalization(pkg)
                g4, m4 = meets_name_length(pkg)
            end
            g5, m5 = meets_julia_name_check(pkg)
            if this_pr_can_use_special_jll_exceptions
                g6 = true
                m6 = ""
            else
                # g6, m6 = meets_standard_initial_version_number(version)
                g6 = true
                m6 = ""
            end

            # g7, m7 = meets_repo_url_requirement(pkg; registry_head = registry_head)
            g7 = true
            m7 = ""

            g8, m8 = meets_compat_for_all_deps(registry_head,
                                               pkg,
                                               version)
            g9_if_jll, m9_if_jll = meets_allowed_jll_nonrecursive_dependencies(registry_head,
                                                                               pkg,
                                                                               version)
            if this_is_jll_package
                g9 = g9_if_jll
                m9 = m9_if_jll
            else
                g9 = true
                m9 = ""
            end

            all_pkg_names = get_all_non_jll_package_names(registry_master)
            g10, m10 = meets_distance_check(pkg, all_pkg_names)

            g11, m11 = meets_name_ascii(pkg)

            @info("JLL-only authors cannot register non-JLL packages.",
                  meets_this_guideline = g0,
                  message = m0)
            @info("Only modifies the files that it's allowed to modify",
                  meets_this_guideline = g1,
                  message = m1)
            @info("TODO: implement this check",
                  meets_this_guideline = g2,
                  message = m2)
            @info("Normal capitalization",
                  meets_this_guideline = g3,
                  message = m3)
            @info("Name not too short",
                  meets_this_guideline = g4,
                  message = m4)
            @info("Name does not include \"julia\" or start with \"Ju\"",
                  meets_this_guideline = g5,
                  message = m5)
            @info("Standard initial version number ",
                  meets_this_guideline = g6,
                  message = m6)
            @info("Repo URL ends with /name.jl.git",
                  meets_this_guideline = g7,
                  message = m7)
            @info("Compat (with upper bound) for all dependencies",
                  meets_this_guideline = g8,
                  message = m8)
            @info("If this is a JLL package, only deps are Pkg, Libdl, and other JLL packages",
                  meets_this_guideline = g9,
                  message = m9)
            @info("Name is not too similar to existing package names",
                  meets_this_guideline = g10,
                  message = m10)
            @info("Name is composed of ASCII characters only",
                  meets_this_guideline = g11,
                  message = m11)
            g0through11 = Bool[g0,
                              g1,
                              g2,
                              g3,
                              g4,
                              g5,
                              g6,
                              g7,
                              g8,
                              g9,
                              g10,
                              g11]
            if !all(g0through11)
                description = "New package. Failed."
                params = Dict("state" => "failure",
                              "context" => "automerge/decision",
                              "description" => description)
                my_retry(() -> GitHub.create_status(api,
                                                    registry,
                                                    current_pr_head_commit_sha;
                                                    auth = auth,
                                                    params = params))
            end
            g12, m12 = meets_version_can_be_pkg_added(registry_head,
                                                    pkg,
                                                    version;
                                                    registry_deps = registry_deps)
            @info("Version can be `Pkg.add`ed",
                  meets_this_guideline = g12,
                  message = m12)
            g13, m13 = meets_version_can_be_imported(registry_head,
                                                     pkg,
                                                     version;
                                                     registry_deps = registry_deps)
            @info("Version can be `import`ed",
                  meets_this_guideline = g13,
                  message = m13)
            g0through13 = Bool[g0,
                               g1,
                               g2,
                               g3,
                               g4,
                               g5,
                               g6,
                               g7,
                               g8,
                               g9,
                               g10,
                               g11,
                               g12,
                               g13]
            allmessages0through13 = String[m0,
                                           m1,
                                           m2,
                                           m3,
                                           m4,
                                           m5,
                                           m6,
                                           m7,
                                           m8,
                                           m9,
                                           m10,
                                           m11,
                                           m12,
                                           m13]
            if all(g0through13) # success
                description = "New package. Approved. name=\"$(pkg)\". sha=\"$(current_pr_head_commit_sha)\""
                params = Dict("state" => "success",
                              "context" => "automerge/decision",
                              "description" => description)
                my_retry(() -> GitHub.create_status(api,
                                                    registry,
                                                    current_pr_head_commit_sha;
                                                    auth = auth,
                                                    params = params))
                this_pr_comment_pass = comment_text_pass(NewPackage(),
                                                         suggest_onepointzero,
                                                         version,
                                                         this_pr_can_use_special_jll_exceptions)
                my_retry(() -> update_automerge_comment!(api,
                                                         registry,
                                                         pr;
                                                         auth = auth,
                                                         body = this_pr_comment_pass,
                                                         whoami = whoami))
                return nothing
            else # failure
                description = "New package. Failed."
                params = Dict("state" => "failure",
                              "context" => "automerge/decision",
                              "description" => description)
                my_retry(() -> GitHub.create_status(api,
                                                    registry,
                                                    current_pr_head_commit_sha;
                                                    auth = auth,
                                                    params = params))
                failingmessages0through13 = allmessages0through13[.!g0through13]
                this_pr_comment_fail = comment_text_fail(NewPackage(),
                                                         failingmessages0through13,
                                                         suggest_onepointzero,
                                                         version)
                my_retry(() -> update_automerge_comment!(api,
                                                         registry,
                                                         pr;
                                                         body = this_pr_comment_fail,
                                                         auth = auth,
                                                         whoami = whoami))
                throw(AutoMergeGuidelinesNotMet("The automerge guidelines were not met."))
            end
        else
            throw(AutoMergeAuthorNotAuthorized("Author $(pr_author_login) is not authorized to automerge. Exiting..."))
        end
    else
        throw(AutoMergePullRequestNotOpen("The pull request is not open. Exiting..."))
    end
end
