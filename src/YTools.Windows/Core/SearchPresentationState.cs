namespace YTools.Core;

/// <summary>Keeps panel height steady while providers finish and input changes.</summary>
public sealed class SearchPresentationState
{
    public int ReservedRows { get; private set; }
    public bool PreservesSelection { get; private set; }
    public void BeginQuery() { ReservedRows = Math.Max(ReservedRows, 3); PreservesSelection = false; }
    public void IncludeResults(int count) { ReservedRows = Math.Max(ReservedRows, Math.Clamp(count, 0, 6)); }
    public void UserSelected() => PreservesSelection = true;
    public void Reset() { ReservedRows = 0; PreservesSelection = false; }
}
