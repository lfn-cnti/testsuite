require "sam"

module CNFManager
  # What kind of suite a test belongs to. Always derived from the namespace a
  # test registers in, so the two cannot disagree.
  enum TestScope
    Workload
    Platform

    def to_tag : String
      self == Workload ? "workload" : "platform"
    end
  end

  # How much a test counts. This is certification policy - essential tests are
  # what `cert` certifies against - and it decides the point value, so no test
  # restates its own score. Normal is the default, so only the tests that carry
  # a policy decision - essential or bonus - say anything about their type.
  enum TestType
    Essential
    Normal
    Bonus

    def to_tag : String
      to_s.downcase
    end

    def pass_points : Int32
      case self
      when Essential then 100
      when Normal    then 5
      else                1
      end
    end

    def fail_points : Int32
      0
    end
  end

  # What a test declares about itself: only the things neither SAM's task graph
  # nor the file layout can tell us. Its category is not among them - that is
  # the aggregate that runs it, read back from the task graph.
  record TestMetadata,
    name : String,
    scope : TestScope,
    type : TestType,
    emoji : String,
    pass_override : Int32?,
    fail_override : Int32? do
    def points(status_name : String) : Int32?
      case status_name
      when "pass" then pass_override || type.pass_points
      when "fail" then fail_override || type.fail_points
      when "skipped", "na" then 0
      end
    end
  end

  # Every test, registered as its task is defined.
  module TestRegistry
    @@tests = {} of String => TestMetadata
    @@category_of : Hash(String, String)? = nil

    def self.register(metadata : TestMetadata)
      @@tests[metadata.name] = metadata
      @@category_of = nil
    end

    def self.all : Hash(String, TestMetadata)
      @@tests
    end

    def self.[]?(name : String) : TestMetadata?
      @@tests[name]?
    end

    def self.names : Array(String)
      @@tests.keys
    end

    # test name => the category group that runs it. Both halves are derived:
    # which groups are categories comes from their own declaration, and which
    # tests they run comes from the task graph. A test cannot claim a category
    # that never runs it, and a category cannot be forgotten from a list.
    def self.category_of : Hash(String, String)
      @@category_of ||= begin
        mapping = {} of String => String
        CNFManager::GroupRegistry.category_paths.each do |path|
          aggregate = Sam.root_namespace.all_tasks.find { |task| task.path == path }
          next unless aggregate
          aggregate.dependency_names.each do |dep|
            mapping[dep.rpartition(":")[2]] = path
          end
        end
        mapping
      end
    end

    # The tag vocabulary the rest of the suite speaks: cert selects tests by
    # tag, scores are totalled by tag, and group criteria name a tag as their
    # scope. The category tag is the aggregate that runs the test.
    def self.tags_for(name : String) : Array(String)
      metadata = @@tests[name]?
      return [] of String unless metadata

      result = [] of String
      if category = category_of[name]?
        result << category
      end
      result << metadata.scope.to_tag
      result << metadata.type.to_tag
      # Every essential test is a cert test and vice versa; cert selection reads
      # the tag, so emit it rather than making callers know they are the same.
      result << "cert" if metadata.type.essential?
      result
    end

    def self.by_tag(tag : String) : Array(String)
      wanted = tag.strip
      @@tests.keys.select { |name| tags_for(name).includes?(wanted) }
    end
  end
end

# Top-level names kept working after a task moved into a namespace. The mapping
# is recorded, not just the task, because SAM matches an exclusion against a
# task's own path: without rewriting, `~k8s_conformance` would match the alias
# and silently fail to exclude the task it points at.
module TaskAliases
  @@aliases = {} of String => String

  def self.register(name : String, target : String)
    @@aliases[name] = target
  end

  def self.[]?(name : String) : String?
    @@aliases[name]?
  end

  # Rewrites `~alias` exclusions to name the task the alias points at.
  def self.resolve_exclusions(argv : Array(String)) : Array(String)
    argv.map do |token|
      next token unless token.starts_with?("~")
      target = @@aliases[token[1..]]?
      target ? "~#{target}" : token
    end
  end
end

def alias_task(name : String, target : String)
  TaskAliases.register(name, target)
  desc "Alias for #{target}"
  task(name, [target]) { |_, _| }
end

# Declares a test: its task, and the few things about it that nothing else can
# tell us. Mixed into both the top level and Sam::Namespace so that `task`
# resolves to the right registrar in each - inside a `namespace` block the
# block's receiver is the namespace, and its tasks must register there.
module ScoredTaskDSL
  # A test's scope follows from where it registers, so it is never declared.
  def scored_task_default_scope : CNFManager::TestScope
    CNFManager::TestScope::Workload
  end

  def scored_task(
    name : String,
    type : CNFManager::TestType = CNFManager::TestType::Normal,
    deps : Array(String) = [] of String,
    emoji : String = "",
    pass : Int32? = nil,
    fail : Int32? = nil,
    &block : Sam::Task, Sam::Args -> Void
  )
    CNFManager::TestRegistry.register(
      CNFManager::TestMetadata.new(
        name: name, scope: scored_task_default_scope, type: type,
        emoji: emoji, pass_override: pass, fail_override: fail))
    task(name, deps, &block)
  end
end

class Sam::Namespace
  include ScoredTaskDSL

  # Defined after the include so it wins: a task registering in the platform
  # namespace is a platform test, and does not have to say so as well.
  def scored_task_default_scope : CNFManager::TestScope
    path.starts_with?("platform") ? CNFManager::TestScope::Platform : CNFManager::TestScope::Workload
  end
end

include ScoredTaskDSL
