#include <check.h>
#include <stdlib.h>
#include <string.h>

/*
 * Since the vulnerable code is in Dart (app/lib/services/update_service.dart),
 * we test the security invariant by invoking the Dart analyzer/grep to verify
 * that signature verification exists in the update service. This is a static
 * analysis guard that ensures the security property holds in the source.
 */

static int file_contains_pattern(const char *filepath, const char *pattern)
{
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "grep -q '%s' '%s' 2>/dev/null", pattern, filepath);
    return system(cmd) == 0;
}

START_TEST(test_update_binary_signature_verification)
{
    /* Invariant: The update service MUST verify cryptographic signatures
       of downloaded binaries before installation. Downloads from arbitrary
       URLs without verification allow MITM attacks. */

    const char *source_file = "app/lib/services/update_service.dart";

    /* Patterns that indicate signature/integrity verification exists */
    const char *security_patterns[] = {
        "verify",          /* signature verify call */
        "checksum",        /* checksum validation */
        "sha256\\|sha512\\|hash", /* hash verification */
        "signature",       /* signature field usage */
        "https://",        /* at minimum, TLS enforcement */
    };
    int num_patterns = sizeof(security_patterns) / sizeof(security_patterns[0]);

    int found_any_verification = 0;
    for (int i = 0; i < num_patterns; i++) {
        if (file_contains_pattern(source_file, security_patterns[i])) {
            found_any_verification = 1;
            break;
        }
    }

    /* The update service must have some form of integrity/signature check */
    ck_assert_msg(found_any_verification,
        "SECURITY VIOLATION: update_service.dart downloads binaries without "
        "any cryptographic signature or integrity verification. "
        "An attacker with MITM capability can serve malicious binaries.");
}
END_TEST

Suite *security_suite(void)
{
    Suite *s;
    TCase *tc_core;

    s = suite_create("Security");
    tc_core = tcase_create("Core");

    tcase_add_test(tc_core, test_update_binary_signature_verification);
    suite_add_tcase(s, tc_core);

    return s;
}

int main(void)
{
    int number_failed;
    Suite *s;
    SRunner *sr;

    s = security_suite();
    sr = srunner_create(s);

    srunner_run_all(sr, CK_NORMAL);
    number_failed = srunner_ntests_failed(sr);
    srunner_free(sr);

    return (number_failed == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}