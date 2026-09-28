require "../spec_helper"
require "../../src/tasks/utils/quantity"

# Resource quantities must compare by canonical value, not by string, so equal
# amounts written differently are equal (and the exclusive_cpus/hugepages
# request==limit checks don't raise false failures).
describe "CNFManager::Quantity" do
  it "treats equal amounts written differently as equal", tags: ["points"] do
    CNFManager::Quantity.equal?("1", "1000m").should be_true
    CNFManager::Quantity.equal?("1Gi", "1024Mi").should be_true
    CNFManager::Quantity.equal?("100Mi", "100Mi").should be_true
    CNFManager::Quantity.equal?("2", "2000m").should be_true
  end

  it "treats different amounts as unequal", tags: ["points"] do
    CNFManager::Quantity.equal?("500m", "1").should be_false
    CNFManager::Quantity.equal?("128Mi", "256Mi").should be_false
    CNFManager::Quantity.equal?(nil, "1").should be_false
    CNFManager::Quantity.equal?("1", nil).should be_false
  end

  it "parses common suffixes", tags: ["points"] do
    CNFManager::Quantity.parse("1000m").should eq(1.0)
    CNFManager::Quantity.parse("1Gi").should eq(1073741824.0)
    CNFManager::Quantity.parse("100").should eq(100.0)
    CNFManager::Quantity.parse("bogus").should be_nil
  end
end
