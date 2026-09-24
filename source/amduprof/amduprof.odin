package amduprof

HAS_UPROF :: #config(HAS_UPROF, false)

when HAS_UPROF {
  foreign import uprof "uprof:lib/x64/AMDProfileController.lib"

  foreign uprof {
    @(link_name="amdProfilePauseImpl")
    ProfilePause :: proc "system" () ---

    @(link_name="amdProfileResumeImpl")
    ProfileResume :: proc "system" () ---

    @(link_name="amdProfileStrictPauseImpl")
    ProfileStrictPause :: proc "system" () ---

    @(link_name="amdProfileStrictResumeImpl")
    ProfileStrictResume :: proc "system" () ---
  }
} else {
    ProfilePause :: proc () {

    }

    ProfileResume :: proc () {

    }

    ProfileStrictPause :: proc () {

    }

    ProfileStrictResume :: proc () {

    }
}
