require "sam"

module CNFManager
  # The criterion a task group passes by.
  #
  #   scope           tag whose tests count; defaults to the group's own name
  #   min_passed      minimum number of those tests that must pass
  #   min_ratio       minimum share of the tests in scope that must pass, as a
  #                   fraction of how many *exist* rather than how many ran. The
  #                   run's own max_passed would shrink when tests are excluded -
  #                   and cert takes an `exclude` argument - so a ratio over it
  #                   could be met by running less. Counting against the declared
  #                   set means a skipped test counts against you, which for a
  #                   certification bar is the honest reading: not verified is
  #                   not passed.
  #   max_failed      how many tests in scope may fail; nil for no limit, which
  #                   is how a group says its other thresholds already account
  #                   for failures rather than treating them as a separate mode
  #
  # All three are thresholds and all are cumulative: every one must hold.
  #
  # The defaults - no floor, no failures tolerated - mean "nothing in this group
  # failed", which is what these groups have always demanded. Only a group with
  # a real policy decision says anything, and today that is only cert.
  #
  # EVERY_TEST is for a group whose members are not identified by a tag of their
  # own. `all` is the case: no test carries an "all" tag, so scoping its
  # criterion to its own name counted nothing at all and made it pass whatever
  # happened underneath it.
  record GroupCriterion,
    scope : String? = nil,
    min_passed : Int32 = 0,
    min_ratio : Float64? = nil,
    max_failed : Int32? = 0

  # Scope covering every test that ran, rather than those carrying one tag.
  EVERY_TEST = ""

  # max_failed value meaning "no limit". Spelled out rather than left as a bare
  # nil, because nil is also what an unset min_ratio looks like: `max_failed:
  # nil` could be misread as "unset, so the default applies", which is the
  # opposite of what it means.
  NO_FAILURE_LIMIT = nil

  # Every task group, registered as its task is defined. A category runs tests
  # and gives them their category; a suite runs other groups.
  module GroupRegistry
    record Group,
      path : String,
      category : Bool,
      criterion : GroupCriterion

    @@groups = {} of String => Group

    def self.register(path : String, category : Bool, criterion : GroupCriterion)
      @@groups[path] = Group.new(path: path, category: category, criterion: criterion)
    end

    def self.all : Hash(String, Group)
      @@groups
    end

    # Only specs use this, to evaluate a criterion without leaving a group
    # behind that the guards would then check.
    def self.unregister(path : String)
      @@groups.delete(path)
    end

    def self.[]?(path : String) : Group?
      @@groups[path]?
    end

    def self.criterion_for(path : String) : GroupCriterion?
      @@groups[path]?.try(&.criterion)
    end

    # The groups that give a test its category. Derived from what registered,
    # so adding a category is one declaration rather than a declaration plus an
    # entry in a list that can silently disagree with it.
    def self.category_paths : Array(String)
      @@groups.select { |_, group| group.category }.keys
    end
  end
end

# Declares a task group: the task, the criterion it passes by, and the verdict
# it reports. Mixed into both the top level and Sam::Namespace so that `task`
# registers in the right place, and so a group inside a namespace knows its own
# full path.
module GroupTaskDSL
  def group_path_prefix : String
    ""
  end

  # A group of tests. Its name is also the tag its members carry, and running it
  # is what gives those members their category. `title` is the heading the score
  # is reported under when it differs from the group's own name.
  def category_task(
    name : String,
    deps : Array(String) = [] of String,
    title : String? = nil,
    scope : String? = nil,
    min_passed : Int32 = 0,
    min_ratio : Float64? = nil,
    max_failed : Int32? = 0
  )
    register_group(name, true, deps, title, true, scope, min_passed, min_ratio, max_failed) { }
  end

  def category_task(
    name : String,
    deps : Array(String) = [] of String,
    title : String? = nil,
    scope : String? = nil,
    min_passed : Int32 = 0,
    min_ratio : Float64? = nil,
    max_failed : Int32? = 0,
    &block : Sam::Task, Sam::Args -> Void
  )
    register_group(name, true, deps, title, true, scope, min_passed, min_ratio, max_failed, &block)
  end

  # A group of other groups: all, workload, platform, cert. `summary` is false
  # for a group that reports its score itself, which only cert does.
  def suite_task(
    name : String,
    deps : Array(String) = [] of String,
    title : String? = nil,
    summary : Bool = true,
    scope : String? = nil,
    min_passed : Int32 = 0,
    min_ratio : Float64? = nil,
    max_failed : Int32? = 0
  )
    register_group(name, false, deps, title, summary, scope, min_passed, min_ratio, max_failed) { }
  end

  def suite_task(
    name : String,
    deps : Array(String) = [] of String,
    title : String? = nil,
    summary : Bool = true,
    scope : String? = nil,
    min_passed : Int32 = 0,
    min_ratio : Float64? = nil,
    max_failed : Int32? = 0,
    &block : Sam::Task, Sam::Args -> Void
  )
    register_group(name, false, deps, title, summary, scope, min_passed, min_ratio, max_failed, &block)
  end

  private def register_group(
    name : String,
    category : Bool,
    deps : Array(String),
    title : String?,
    summary : Bool,
    scope : String?,
    min_passed : Int32,
    min_ratio : Float64?,
    max_failed : Int32?,
    &block : Sam::Task, Sam::Args -> Void
  )
    path = "#{group_path_prefix}#{name}"
    criterion = CNFManager::GroupCriterion.new(scope: scope, min_passed: min_passed,
                                               min_ratio: min_ratio,
                                               max_failed: max_failed)
    CNFManager::GroupRegistry.register(path, category, criterion)

    task(name, deps) do |t, args|
      Log.for(path).debug { "#{path} args: #{args.raw}" }
      block.call(t, args)

      # Reporting used to be copied into every group's body. The verdict in
      # particular was keyed by the group's *display* name there, so the three
      # groups whose display name differs from their own - compatibility,
      # resilience, observability - looked up a criterion that did not exist and
      # silently reported nothing.
      if summary
        if category
          stdout_score(path, title || path)
        else
          stdout_suite_score(path, title || path, criterion)
        end
      end
      stdout_group_verdict(path)
    end
  end
end

class Sam::Namespace
  include GroupTaskDSL

  # Defined after the include so it wins: a group inside `namespace "platform"`
  # is platform:<name>, which is the path its criterion and members are keyed by.
  def group_path_prefix : String
    path
  end
end

include GroupTaskDSL
