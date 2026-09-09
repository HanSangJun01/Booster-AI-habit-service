package com.booster.personallocation.service;

import com.booster.personallocation.domain.PersonalLocation;
import com.booster.personallocation.dto.LocationRequest;
import com.booster.personallocation.dto.LocationResponse;
import com.booster.personallocation.repository.PersonalLocationRepository;
import com.booster.shared.common.BusinessException;
import com.booster.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class PersonalLocationService {

    private final PersonalLocationRepository personalLocationRepository;
    private final UserRepository userRepository;

    /** 최초 1회 등록. 이미 등록되어 있으면 409. */
    @Transactional
    public LocationResponse register(Long userId, LocationRequest request) {
        requireActive(userId); // (BS-30 7차 F3) 탈퇴 계정 쓰기 차단
        if (personalLocationRepository.existsById(userId)) {
            throw BusinessException.conflict("LOCATION_ALREADY_REGISTERED",
                    "이미 등록된 위치가 있습니다. 수정 API를 사용하세요.");
        }
        try {
            PersonalLocation saved = personalLocationRepository.save(PersonalLocation.create(
                    userId, request.lat(), request.lng(), request.radiusMeters(), request.placeName()));
            return LocationResponse.from(saved);
        } catch (DataIntegrityViolationException e) {
            // (BS-30 7차 C#7) 동시 등록 레이스 → PK 위반을 도메인 에러로 변환(일반 500/DATA_CONFLICT 대신).
            throw BusinessException.conflict("LOCATION_ALREADY_REGISTERED",
                    "이미 등록된 위치가 있습니다. 수정 API를 사용하세요.");
        }
    }

    /**
     * 인증 장소 변경 예약. 미등록 시 404.
     *
     * <p><b>즉시 반영하지 않는다.</b> 예전에는 바로 바뀌어서, 인증 직전에 지금 있는 자리로
     * 장소를 옮기면 어디서든 통과할 수 있었다. 주간 목표와 같은 방식으로 예약해 두고
     * 다음 달 1일에 함께 반영한다.
     *
     * <p>같은 달에 다시 호출하면 예약 값을 덮어쓴다(마지막 예약이 이긴다). 지금 장소와 같은
     * 값을 보내면 예약을 취소한 것으로 본다 — 앱에서 "역시 그대로 둘래"를 표현할 방법이 필요하다.
     */
    @Transactional
    public LocationResponse update(Long userId, LocationRequest request) {
        requireActive(userId); // (BS-30 7차 F3) 탈퇴 계정 쓰기 차단
        PersonalLocation location = personalLocationRepository.findById(userId)
                .orElseThrow(() -> BusinessException.notFound(
                        "LOCATION_NOT_FOUND", "등록된 위치가 없습니다."));

        boolean sameAsCurrent = location.getLat() == request.lat()
                && location.getLng() == request.lng()
                && location.getRadiusMeters() == request.radiusMeters();
        if (sameAsCurrent) {
            location.cancelLocationReservation();
        } else {
            location.reserveLocation(request.lat(), request.lng(),
                    request.radiusMeters(), request.placeName());
        }
        return LocationResponse.from(location);
    }

    private void requireActive(Long userId) {
        if (!userRepository.existsByIdAndActiveTrue(userId)) {
            throw BusinessException.forbidden("INACTIVE_USER", "비활성(탈퇴) 계정입니다.");
        }
    }

    @Transactional(readOnly = true)
    public LocationResponse get(Long userId) {
        PersonalLocation location = personalLocationRepository.findById(userId)
                .orElseThrow(() -> BusinessException.notFound(
                        "LOCATION_NOT_FOUND", "등록된 위치가 없습니다."));
        return LocationResponse.from(location);
    }
}
